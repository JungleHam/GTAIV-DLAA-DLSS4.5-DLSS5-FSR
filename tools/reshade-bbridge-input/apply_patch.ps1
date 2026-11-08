param(
    [Parameter(Mandatory=$true)]
    [string]$SourceDir
)

$ErrorActionPreference = 'Stop'
$SourceDir = (Resolve-Path $SourceDir).Path
$inputPath = Join-Path $SourceDir 'source\input_windows.cpp'
$guiPath   = Join-Path $SourceDir 'source\runtime_gui.cpp'

if (!(Test-Path $inputPath) -or !(Test-Path $guiPath)) {
    throw "ReShade source files not found under: $SourceDir"
}

function Read-Normalized([string]$Path) {
    return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Normalize-Text([string]$Text) {
    return ($Text -replace "`r`n", "`n")
}

function Write-CrlfUtf8([string]$Path, [string]$Text) {
    $Text = $Text -replace "`r`n", "`n"
    $Text = $Text -replace "`n", "`r`n"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

$input = Read-Normalized $inputPath
if (!$input.Contains('#include <vector>')) {
    $includeAnchor = '#include <unordered_map>'
    if (!$input.Contains($includeAnchor)) {
        throw 'Could not find input_windows.cpp unordered_map include anchor.'
    }
    $input = $input.Replace($includeAnchor, $includeAnchor + [Environment]::NewLine + '#include <vector>')
}
$gui   = Read-Normalized $guiPath

if ($input.Contains('b-bridge cross-process input relay')) {
    Write-Host 'input_windows.cpp already patched.'
} else {
    $anchor = @'
static std::atomic<bool> s_block_cursor_warping = false;

'@
    $anchor = Normalize-Text $anchor

    if (!$input.Contains($anchor)) {
        throw 'Could not find input_windows.cpp global-state anchor. Wrong ReShade version? Expected v6.8.0.'
    }

    $relay = @'
static std::atomic<HWND> s_bridge_input_window = nullptr;
static std::atomic<HWND> s_bridge_channel_window = nullptr;
static std::atomic<DWORD> s_bridge_process_id = 0;
static std::atomic<bool> s_bridge_worker_started = false;
static std::atomic<UINT> s_bridge_ui_active_msg = 0;

// b-bridge uses a registered message to hand the renderer worker-thread ID
// back to the x86 client. A normal SendMessageTimeout return is NOT proof
// that RemixWndProc received that message, so wait for an explicit ACK.
struct bbridge_window_candidates
{
    DWORD process_id;
    std::vector<HWND> windows;
};

static void bbridge_add_window_candidate(bbridge_window_candidates &list, HWND hwnd)
{
    if (hwnd == nullptr || !IsWindow(hwnd))
        return;

    DWORD process_id = 0;
    GetWindowThreadProcessId(hwnd, &process_id);
    if (process_id != list.process_id)
        return;

    if (std::find(list.windows.begin(), list.windows.end(), hwnd) == list.windows.end())
        list.windows.push_back(hwnd);
}

static BOOL CALLBACK bbridge_enum_child_windows(HWND hwnd, LPARAM parameter)
{
    auto *list = reinterpret_cast<bbridge_window_candidates *>(parameter);
    bbridge_add_window_candidate(*list, hwnd);
    return TRUE;
}

static BOOL CALLBACK bbridge_enum_top_windows(HWND hwnd, LPARAM parameter)
{
    auto *list = reinterpret_cast<bbridge_window_candidates *>(parameter);
    DWORD process_id = 0;
    GetWindowThreadProcessId(hwnd, &process_id);
    if (process_id == list->process_id)
    {
        bbridge_add_window_candidate(*list, hwnd);
        EnumChildWindows(hwnd, bbridge_enum_child_windows, parameter);
    }
    return TRUE;
}

static std::vector<HWND> bbridge_collect_handshake_windows(HWND preferred, DWORD process_id)
{
    bbridge_window_candidates list = { process_id, {} };
    bbridge_add_window_candidate(list, preferred);
    EnumWindows(bbridge_enum_top_windows, reinterpret_cast<LPARAM>(&list));
    return list.windows;
}

static DWORD WINAPI bbridge_input_worker(LPVOID)
{
    MSG msg = {};
    // PostThreadMessage fails until this thread owns a message queue.
    PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);

    const UINT handshake_msg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG");
    const UINT ack_msg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_INPUT_RELAY_ACK_MSG");
    const UINT ui_active_msg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");
    s_bridge_ui_active_msg.store(ui_active_msg);

    bool connected = false;
    DWORD last_retry_log = 0;

    while (!connected)
    {
        const HWND preferred = s_bridge_input_window.load();
        const DWORD process_id = s_bridge_process_id.load();

        if (process_id != 0 && handshake_msg != 0 && ack_msg != 0)
        {
            const std::vector<HWND> candidates =
                bbridge_collect_handshake_windows(preferred, process_id);

            for (const HWND candidate : candidates)
            {
                DWORD candidate_pid = 0;
                const DWORD candidate_thread =
                    GetWindowThreadProcessId(candidate, &candidate_pid);
                if (candidate_pid != process_id || candidate_thread == 0)
                    continue;

                DWORD_PTR receiver_result = 0;
                const LRESULT delivered = SendMessageTimeoutW(
                    candidate,
                    handshake_msg,
                    static_cast<WPARAM>(GetCurrentThreadId()),
                    0,
                    SMTO_ABORTIFHUNG | SMTO_BLOCK,
                    750,
                    &receiver_result);

                if (delivered == 0)
                    continue;

                // The target window may have processed the message without
                // passing it through b-bridge. Only the explicit ACK proves
                // that MessageChannelClient stored our worker thread ID.
                const DWORD ack_start = GetTickCount();
                while (GetTickCount() - ack_start < 750)
                {
                    MSG ack = {};
                    if (PeekMessageW(&ack, nullptr, ack_msg, ack_msg, PM_REMOVE))
                    {
                        if (ack.wParam == 1)
                        {
                            connected = true;
                            break;
                        }
                    }
                    Sleep(10);
                }

                if (connected)
                {
                    s_bridge_channel_window.store(candidate);
                    reshade::log::message(
                        reshade::log::level::info,
                        "b-bridge input relay: explicit handshake ACK from HWND %p (PID %lu, thread %lu).",
                        candidate, process_id, candidate_thread);

                    if (ui_active_msg != 0)
                        PostMessageW(candidate, ui_active_msg, 0, 0);
                    break;
                }
            }
        }

        if (!connected)
        {
            const DWORD now = GetTickCount();
            if (now - last_retry_log >= 3000)
            {
                reshade::log::message(
                    reshade::log::level::warning,
                    "b-bridge input relay: waiting for explicit handshake ACK (preferred HWND %p, PID %lu).",
                    preferred, process_id);
                last_retry_log = now;
            }
            Sleep(500);
        }
    }

    while (GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        if (msg.message == ack_msg)
            continue;

        const HWND input_hwnd = s_bridge_input_window.load();
        if (input_hwnd == nullptr || !IsWindow(input_hwnd))
            continue;

        // PostThreadMessage creates MSG entries without an HWND. ReShade's
        // normal input router keys on HWND, so restore its registered window.
        msg.hwnd = input_hwnd;

        if (msg.message >= WM_MOUSEFIRST && msg.message <= WM_MOUSELAST)
        {
            POINT pt = {
                static_cast<short>(LOWORD(msg.lParam)),
                static_cast<short>(HIWORD(msg.lParam))
            };
            ClientToScreen(input_hwnd, &pt);
            msg.pt = pt;
        }
        else
        {
            GetCursorPos(&msg.pt);
        }

        const bool blocked = reshade::input::handle_window_message(&msg);
        if ((msg.message == WM_KEYDOWN || msg.message == WM_KEYUP) &&
            (msg.wParam == VK_HOME || msg.wParam == VK_F11))
        {
            reshade::log::message(
                reshade::log::level::info,
                "b-bridge input relay: worker received key message=0x%X VK=0x%02X HWND=%p blocked=%d.",
                msg.message, static_cast<unsigned int>(msg.wParam), input_hwnd, blocked ? 1 : 0);
        }
    }

    return 0;
}

static void ensure_bbridge_input_worker(HWND hwnd)
{
    s_bridge_input_window.store(hwnd);

    DWORD process_id = 0;
    GetWindowThreadProcessId(hwnd, &process_id);
    if (process_id != 0)
        s_bridge_process_id.store(process_id);

    bool expected = false;
    if (!s_bridge_worker_started.compare_exchange_strong(expected, true))
        return;

    HANDLE thread = CreateThread(nullptr, 0, bbridge_input_worker, nullptr, 0, nullptr);
    if (thread == nullptr)
    {
        s_bridge_worker_started.store(false);
        reshade::log::message(reshade::log::level::error,
            "b-bridge input relay: failed to create worker thread (error %lu).", GetLastError());
        return;
    }

    CloseHandle(thread);
}

void reshade_bridge_notify_ui_state(void *window, bool open)
{
    const HWND input_hwnd = static_cast<HWND>(window);
    if (input_hwnd == nullptr || !IsWindow(input_hwnd))
        return;

    DWORD owner_pid = 0;
    GetWindowThreadProcessId(input_hwnd, &owner_pid);
    if (owner_pid == GetCurrentProcessId())
        return; // Ordinary in-process ReShade game: leave behavior untouched.

    UINT msg = s_bridge_ui_active_msg.load();
    if (msg == 0)
    {
        msg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");
        s_bridge_ui_active_msg.store(msg);
    }

    HWND channel_hwnd = s_bridge_channel_window.load();
    if (channel_hwnd == nullptr || !IsWindow(channel_hwnd))
        channel_hwnd = input_hwnd;

    if (msg != 0)
        PostMessageW(channel_hwnd, msg, open ? 1 : 0, 0);
}

'@
    $relay = Normalize-Text $relay
    $input = $input.Replace($anchor, $relay)

    $oldCheck = @'
	DWORD process_id = 0;
	GetWindowThreadProcessId(static_cast<HWND>(window), &process_id);
	if (process_id != GetCurrentProcessId())
	{
		reshade::log::message(reshade::log::level::warning, "Cannot capture input for window %p created by a different process (%lu).", window, process_id);
		return nullptr;
	}
'@
    $oldCheck = Normalize-Text $oldCheck
    $newCheck = @'
	DWORD process_id = 0;
	GetWindowThreadProcessId(static_cast<HWND>(window), &process_id);
	const bool bbridge_foreign_window = process_id != GetCurrentProcessId();
	if (bbridge_foreign_window)
	{
		reshade::log::message(reshade::log::level::info,
			"b-bridge input relay: accepting foreign render window %p owned by process %lu.", window, process_id);
	}
'@
    $newCheck = Normalize-Text $newCheck
    if (!$input.Contains($oldCheck)) {
        throw 'Could not find ReShade cross-process rejection block. Wrong ReShade version? Expected v6.8.0.'
    }
    $input = $input.Replace($oldCheck, $newCheck)

    $oldInsert = @'
	const auto insert = s_windows.emplace(static_cast<HWND>(window), std::weak_ptr<input>());

	if (insert.second || insert.first->second.expired())
'@
    $oldInsert = Normalize-Text $oldInsert
    $newInsert = @'
	const auto insert = s_windows.emplace(static_cast<HWND>(window), std::weak_ptr<input>());

	if (bbridge_foreign_window)
		ensure_bbridge_input_worker(static_cast<HWND>(window));

	if (insert.second || insert.first->second.expired())
'@
    $newInsert = Normalize-Text $newInsert
    if (!$input.Contains($oldInsert)) {
        throw 'Could not find ReShade window-map insertion block.'
    }
    $input = $input.Replace($oldInsert, $newInsert)

    Write-CrlfUtf8 $inputPath $input
    Write-Host 'Patched source\input_windows.cpp'
}

# Record whether forwarded Home/F11 messages actually reach ReShade's input object.
$diagKey = "const bool bbridge_diag_key = (details.message == WM_KEYDOWN || details.message == WM_KEYUP) && (details.wParam == VK_HOME || details.wParam == VK_F11);"
if (!$input.Contains($diagKey)) {
    $tab = [string][char]9
    $nl = [Environment]::NewLine
    $detailsAnchor = $tab + 'MSG details = *static_cast<const MSG *>(message_data);'
    if (!$input.Contains($detailsAnchor)) { throw 'Could not find ReShade MSG details anchor.' }
    $input = $input.Replace($detailsAnchor, $detailsAnchor + $nl + $tab + $diagKey)

    $missAnchor = $tab + 'if (input_window == s_windows.end())' + $nl + $tab + $tab + 'return false;'
    $missReplacement = @'
	if (input_window == s_windows.end())
	{
		if (bbridge_diag_key)
			reshade::log::message(reshade::log::level::warning, "b-bridge input relay: key VK 0x%02X arrived for HWND %p but no ReShade input object is registered.", static_cast<unsigned int>(details.wParam), details.hwnd);
		return false;
	}
'@
    if (!$input.Contains($missAnchor)) { throw 'Could not find ReShade input-window miss anchor.' }
    $input = $input.Replace($missAnchor, (Normalize-Text $missReplacement))

    $nullAnchor = $tab + 'if (input == nullptr)' + $nl + $tab + $tab + 'return false;'
    $nullReplacement = @'
	if (input == nullptr)
	{
		if (bbridge_diag_key)
			reshade::log::message(reshade::log::level::warning, "b-bridge input relay: ReShade input object expired for HWND %p.", details.hwnd);
		return false;
	}
	if (bbridge_diag_key)
		reshade::log::message(reshade::log::level::info, "b-bridge input relay: matched ReShade input object for VK 0x%02X HWND %p.", static_cast<unsigned int>(details.wParam), details.hwnd);
'@
    if (!$input.Contains($nullAnchor)) { throw 'Could not find ReShade input-object null anchor.' }
    $input = $input.Replace($nullAnchor, (Normalize-Text $nullReplacement))

    $returnAnchor = $tab + 'return (is_mouse_message && input->is_blocking_mouse_input()) || (is_keyboard_message && input->is_blocking_keyboard_input());'
    $returnReplacement = $tab + 'if (bbridge_diag_key)' + $nl + $tab + $tab + 'reshade::log::message(reshade::log::level::info, "b-bridge input relay: updated VK 0x%02X state=0x%02X.", static_cast<unsigned int>(details.wParam), static_cast<unsigned int>(input->_keys[details.wParam]));' + $nl + $returnAnchor
    if (!$input.Contains($returnAnchor)) { throw 'Could not find ReShade input-handler return anchor.' }
    $input = $input.Replace($returnAnchor, $returnReplacement)
}
[IO.File]::WriteAllText($inputPath, $input, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Patched ReShade input relay diagnostics'

if ($gui.Contains('reshade_bridge_notify_ui_state(get_hwnd(), open);')) {
    Write-Host 'runtime_gui.cpp already patched.'
} else {
    $oldExtern = 'extern bool resolve_path(std::filesystem::path &path, std::error_code &ec, const std::filesystem::path &base = g_reshade_base_path);'
    $newExtern = $oldExtern + "`nextern void reshade_bridge_notify_ui_state(void *window, bool open);"
    if (!$gui.Contains($oldExtern)) {
        throw 'Could not find runtime_gui.cpp extern anchor.'
    }
    $gui = $gui.Replace($oldExtern, $newExtern)

    $oldOverlay = @'
	_show_overlay = open;

	if (open)
'@
    $oldOverlay = Normalize-Text $oldOverlay
    $newOverlay = @'
	_show_overlay = open;

	// Tell the GTA-side b-bridge WndProc when ReShade owns input. The bridge then
	// swallows those input messages before the game can react to UI clicks/keys.
	reshade_bridge_notify_ui_state(get_hwnd(), open);

	if (open)
'@
    $newOverlay = Normalize-Text $newOverlay
    if (!$gui.Contains($oldOverlay)) {
        throw 'Could not find runtime::open_overlay body in runtime_gui.cpp.'
    }
    $gui = $gui.Replace($oldOverlay, $newOverlay)

    Write-CrlfUtf8 $guiPath $gui
    Write-Host 'Patched source\runtime_gui.cpp'
}


# Log when the configured ReShade overlay shortcut is actually recognized.
if (!$gui.Contains('M3K-BBRIDGE-OVERLAY-KEY-TRACE')) {
    $oldShortcut = @'
		else if (!_ignore_shortcuts && _input->is_key_pressed(_overlay_key_data, _force_shortcut_modifiers) && _imgui_context->ActiveId == 0)
			show_overlay = !_show_overlay;
'@
    $oldShortcut = Normalize-Text $oldShortcut
    $newShortcut = @'
		else if (!_ignore_shortcuts && _input->is_key_pressed(_overlay_key_data, _force_shortcut_modifiers))
		{
			// M3K-BBRIDGE-OVERLAY-KEY-TRACE
			if (_imgui_context->ActiveId == 0)
			{
				reshade::log::message(reshade::log::level::info, "b-bridge input relay: ReShade overlay shortcut recognized (VK %u).", _overlay_key_data[0]);
				show_overlay = !_show_overlay;
			}
			else
			{
				reshade::log::message(reshade::log::level::info, "b-bridge input relay: overlay shortcut received while ImGui ActiveId=%u.", static_cast<unsigned int>(_imgui_context->ActiveId));
			}
		}
'@
    $newShortcut = Normalize-Text $newShortcut
    if (!$gui.Contains($oldShortcut)) { throw 'Could not find ReShade overlay shortcut evaluation block.' }
    $gui = $gui.Replace($oldShortcut, $newShortcut)
    Write-CrlfUtf8 $guiPath $gui
}

Write-Host 'ReShade 6.8.0 b-bridge input patch applied successfully.' -ForegroundColor Green
