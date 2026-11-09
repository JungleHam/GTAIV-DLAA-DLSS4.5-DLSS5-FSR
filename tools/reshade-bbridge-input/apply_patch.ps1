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
static std::atomic<bool> s_block_cursor_warping = false;

// b-bridge cross-process input relay
// GTAIV.exe owns the HWND, while ReShade runs in NvRemixBridge.exe. b-bridge already
// forwards keyboard/mouse Windows messages through this dormant RTX Remix channel.
// Restore the renderer-side endpoint and feed those messages into ReShade's normal
// input object, so the stock overlay/ImGui path can remain unchanged.
static std::atomic<HWND> s_bridge_window = nullptr;
static std::atomic<bool> s_bridge_worker_started = false;
static std::atomic<UINT> s_bridge_ui_active_msg = 0;

static DWORD WINAPI bbridge_input_worker(LPVOID)
{
    MSG msg = {};
    // PostThreadMessage fails until the target thread owns a message queue.
    PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);

    const UINT handshake_msg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG");
    const UINT ui_active_msg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");
    s_bridge_ui_active_msg.store(ui_active_msg);

    bool connected = false;
    while (!connected)
    {
        const HWND hwnd = s_bridge_window.load();
        if (hwnd != nullptr && IsWindow(hwnd) && handshake_msg != 0)
        {
            DWORD_PTR receiver_result = 0;
            const LRESULT ok = SendMessageTimeoutW(
                hwnd,
                handshake_msg,
                static_cast<WPARAM>(GetCurrentThreadId()),
                0,
                SMTO_ABORTIFHUNG | SMTO_BLOCK,
                1000,
                &receiver_result);

            if (ok != 0)
            {
                connected = true;
                reshade::log::message(reshade::log::level::info,
                    "b-bridge input relay: handshake complete with foreign game window %p (thread %lu).",
                    hwnd, GetCurrentThreadId());

                if (ui_active_msg != 0)
                    PostMessageW(hwnd, ui_active_msg, 0, 0);
                break;
            }
        }

        Sleep(500);
    }

    while (GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        const HWND hwnd = s_bridge_window.load();
        if (hwnd == nullptr || !IsWindow(hwnd))
            continue;

        // PostThreadMessage creates MSG entries without an HWND. ReShade's normal
        // input router keys on HWND, so restore the game's foreign HWND here.
        msg.hwnd = hwnd;

        // b-bridge's DirectInput translator encodes its virtual mouse position in
        // lParam as client coordinates. Convert that to screen coordinates because
        // handle_window_message() will convert MSG::pt back to client coordinates.
        if (msg.message >= WM_MOUSEFIRST && msg.message <= WM_MOUSELAST)
        {
            POINT pt = {
                static_cast<short>(LOWORD(msg.lParam)),
                static_cast<short>(HIWORD(msg.lParam))
            };
            ClientToScreen(hwnd, &pt);
            msg.pt = pt;
        }
        else
        {
            GetCursorPos(&msg.pt);
        }

        reshade::input::handle_window_message(&msg);
    }

    return 0;
}

static void ensure_bbridge_input_worker(HWND hwnd)
{
    s_bridge_window.store(hwnd);

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
    const HWND hwnd = static_cast<HWND>(window);
    if (hwnd == nullptr || !IsWindow(hwnd))
        return;

    DWORD owner_pid = 0;
    GetWindowThreadProcessId(hwnd, &owner_pid);
    if (owner_pid == GetCurrentProcessId())
        return; // Ordinary in-process ReShade game: leave behavior untouched.

    UINT msg = s_bridge_ui_active_msg.load();
    if (msg == 0)
    {
        msg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");
        s_bridge_ui_active_msg.store(msg);
    }

    if (msg != 0)
        PostMessageW(hwnd, msg, open ? 1 : 0, 0);
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


# GTA IV's internal rendering dimensions can be lower than the final Vulkan
# output. ReShade normally maps input coordinates by render/client dimensions.
# b-bridge's forwarded mouse coordinates can already be in the reduced render
# space, while GetClientRect sees the native-size presenter window. Align
# ReShade's effective input bounds with the ACTIVE reconstruction profile.
if ($gui.Contains('m3k_bbridge_ui_render_scale(')) {
    Write-Host 'runtime_gui.cpp render-scale mouse mapping already patched.'
} else {
    $scaleHelperAnchor = 'extern void reshade_bridge_notify_ui_state(void *window, bool open);'
    $scaleHelper = @'
extern void reshade_bridge_notify_ui_state(void *window, bool open);

// M3K-BBRIDGE-RENDER-SCALE-MOUSE
// Only enabled for the foreign GTAIV.exe window handled by the b-bridge relay.
// Ordinary in-process ReShade applications retain the upstream input behavior.
static float m3k_bbridge_ui_render_scale(void *window)
{
    if (window == nullptr)
        return 1.0f;

    DWORD owner_pid = 0;
    if (GetWindowThreadProcessId(static_cast<HWND>(window), &owner_pid) == 0 ||
        owner_pid == GetCurrentProcessId())
        return 1.0f;

    static const std::filesystem::path ini_path = g_reshade_base_path / L"m3k-nr.ini";
    if (GetFileAttributesW(ini_path.c_str()) == INVALID_FILE_ATTRIBUTES)
        return 1.0f;

    // ReShade UI and M3K's live selector share this INI. Cache the read briefly
    // to avoid repeated file I/O on every frame, but follow live preset changes.
    static thread_local ULONGLONG last_poll = 0;
    static thread_local float cached_scale = 1.0f;
    const ULONGLONG now = GetTickCount64();
    if (last_poll == 0 || now - last_poll > 200)
    {
        last_poll = now;
        const int master_enabled =
            GetPrivateProfileIntW(L"M3K", L"MasterEnabled", 1, ini_path.c_str());
        const int backend =
            GetPrivateProfileIntW(L"M3K", L"ScalingTechnology", 1, ini_path.c_str());

        float scale = 1.0f;
        if (master_enabled != 0 && backend == 1) // NVIDIA DLAA / DLSS SR
        {
            switch (GetPrivateProfileIntW(L"M3K", L"SRProfile", 0, ini_path.c_str()))
            {
            case 1: scale = 0.77f; break;  // Ultra Quality
            case 2: scale = 0.667f; break; // Quality
            case 3: scale = 0.58f; break;  // Balanced
            case 4: scale = 0.50f; break;  // Performance
            case 5: scale = 0.333f; break; // Ultra Performance
            case 6: // Custom 10-100%
                scale = std::clamp(
                    GetPrivateProfileIntW(L"M3K", L"CustomScalePercent", 77, ini_path.c_str()),
                    10, 100) / 100.0f;
                break;
            default: break; // DLAA/native 100%
            }
        }
        else if (master_enabled != 0 && backend == 2) // AMD FSR
        {
            scale = std::clamp(
                GetPrivateProfileIntW(L"M3K", L"FSRScalePermille", 1000, ini_path.c_str()),
                100, 1000) / 1000.0f;
        }
        cached_scale = std::clamp(scale, 0.10f, 1.0f);
    }

    return cached_scale;
}
'@
    $scaleHelper = Normalize-Text $scaleHelper
    if (!$gui.Contains($scaleHelperAnchor)) {
        throw 'Could not find b-bridge runtime_gui.cpp helper anchor.'
    }
    $gui = $gui.Replace($scaleHelperAnchor, $scaleHelper)

    $mouseAnchor = @'
		_input->max_mouse_position(max_position);
		imgui_io.AddMousePosEvent(
'@
    $mouseReplacement = @'
		_input->max_mouse_position(max_position);

		// M3K-BBRIDGE-RENDER-SCALE-MOUSE-LIMIT
		// Mouse lParam is forwarded in the lower-resolution GTA render space,
		// but the ReShade menu is drawn over the full-size output surface.
		// Use the smaller of the window client extent or the true render extent.
		// Thus no double-scaling occurs when the game window itself is reduced.
		const float m3k_scale = m3k_bbridge_ui_render_scale(get_hwnd());
		if (m3k_scale < 0.999f)
		{
			const unsigned int render_mouse_w = std::max(
				1u, static_cast<unsigned int>(imgui_io.DisplaySize.x * m3k_scale + 0.5f));
			const unsigned int render_mouse_h = std::max(
				1u, static_cast<unsigned int>(imgui_io.DisplaySize.y * m3k_scale + 0.5f));
			max_position[0] = std::min(max_position[0], render_mouse_w);
			max_position[1] = std::min(max_position[1], render_mouse_h);
		}
		max_position[0] = std::max(max_position[0], 1u);
		max_position[1] = std::max(max_position[1], 1u);
		imgui_io.AddMousePosEvent(
'@
    $mouseAnchor = Normalize-Text $mouseAnchor
    $mouseReplacement = Normalize-Text $mouseReplacement
    if (!$gui.Contains($mouseAnchor)) {
        throw 'Could not find runtime_gui.cpp AddMousePosEvent scaling anchor. Expected ReShade 6.8.0.'
    }
    $gui = $gui.Replace($mouseAnchor, $mouseReplacement)
    Write-CrlfUtf8 $guiPath $gui
    Write-Host 'Patched runtime_gui.cpp with render-scale-aware ReShade mouse mapping.'
}

Write-Host 'ReShade 6.8.0 b-bridge input patch applied successfully.' -ForegroundColor Green
