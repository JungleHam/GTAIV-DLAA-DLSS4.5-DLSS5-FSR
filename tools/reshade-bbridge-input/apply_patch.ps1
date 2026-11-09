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


# runtime_gui.cpp uses Win32 APIs for the bridge-specific mouse-bound correction.
if (!$gui.Contains('#include <Windows.h>')) {
    $includeAnchor = '#include "platform_utils.hpp"'
    if (!$gui.Contains($includeAnchor)) {
        throw 'Cannot locate runtime_gui.cpp platform include anchor.'
    }
    $win32Includes = @'
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
'@
    $win32Includes = Normalize-Text $win32Includes
    $gui = $gui.Replace($includeAnchor, $includeAnchor + "`n" + $win32Includes)
}

# M3K virtualizes GetClientRect in the 32-bit GTA IV process to the logical
# RenderWidth/RenderHeight, while the 64-bit NvRemixBridge process sees the
# physical output client size. b-bridge forwards DirectInput mouse coordinates
# in that logical space. ReShade's upstream max_mouse_position() runs in the
# 64-bit process and therefore sees the larger physical client rectangle.
# Give ReShade the exact logical input bounds so its existing
# DisplaySize/max_mouse_position normalization maps the cursor to full output.
if ($gui.Contains('m3k_bbridge_ui_logical_mouse_bounds(')) {
    Write-Host 'runtime_gui.cpp logical-client mouse bounds already patched.'
} else {
    $boundsHelperAnchor = 'extern void reshade_bridge_notify_ui_state(void *window, bool open);'
    $boundsHelper = @'
extern void reshade_bridge_notify_ui_state(void *window, bool open);

// M3K-BBRIDGE-LOGICAL-MOUSE-BOUNDS
// Use the same exact logical client dimensions that the GTA-side A2-S2.1
// GetClientRect virtualization presents to the 32-bit game process.
static void m3k_bbridge_ui_logical_mouse_bounds(void *window, unsigned int max_position[2])
{
    if (window == nullptr || max_position == nullptr)
        return;

    DWORD owner_pid = 0;
    if (GetWindowThreadProcessId(static_cast<HWND>(window), &owner_pid) == 0 ||
        owner_pid == GetCurrentProcessId())
        return; // Do not alter ordinary in-process ReShade.

    static thread_local ULONGLONG next_poll = 0;
    static thread_local bool cached_enabled = false;
    static thread_local unsigned int cached_width = 0;
    static thread_local unsigned int cached_height = 0;
    static thread_local unsigned int logged_width = 0;
    static thread_local unsigned int logged_height = 0;

    const ULONGLONG now = GetTickCount64();
    if (now >= next_poll)
    {
        next_poll = now + 250;
        const std::filesystem::path ini_path =
            g_target_executable_path.parent_path() / L"m3k-nr.ini";

        if (GetFileAttributesW(ini_path.c_str()) != INVALID_FILE_ATTRIBUTES)
        {
            cached_enabled =
                GetPrivateProfileIntW(L"M3K", L"VirtualizeGameClient", 0, ini_path.c_str()) != 0;
            cached_width =
                GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, ini_path.c_str());
            cached_height =
                GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, ini_path.c_str());
        }
        else
        {
            cached_enabled = false;
            cached_width = cached_height = 0;
        }
    }

    if (!cached_enabled || cached_width == 0 || cached_height == 0)
        return;

    // max_position initially contains the real physical client extent. The
    // logical dimensions must not exceed that physical extent, but otherwise
    // must replace it exactly (not an estimated DLSS preset percentage).
    const unsigned int physical_width = max_position[0];
    const unsigned int physical_height = max_position[1];
    const unsigned int logical_width = std::min(physical_width, cached_width);
    const unsigned int logical_height = std::min(physical_height, cached_height);
    if (logical_width == 0 || logical_height == 0)
        return;

    max_position[0] = logical_width;
    max_position[1] = logical_height;

    if (logged_width != logical_width || logged_height != logical_height)
    {
        logged_width = logical_width;
        logged_height = logical_height;
        reshade::log::message(reshade::log::level::info,
            "[M3K-BBRIDGE-LOGICAL-MOUSE-BOUNDS] logical=%ux%u physical-client=%ux%u",
            logical_width, logical_height, physical_width, physical_height);
    }
}
'@
    $boundsHelper = Normalize-Text $boundsHelper
    if (!$gui.Contains($boundsHelperAnchor)) {
        throw 'Could not find runtime_gui.cpp bridge helper anchor.'
    }
    $gui = $gui.Replace($boundsHelperAnchor, $boundsHelper)

    $mouseAnchor = @'
		_input->max_mouse_position(max_position);
		imgui_io.AddMousePosEvent(
'@
    $mouseReplacement = @'
		_input->max_mouse_position(max_position);

		// M3K-BBRIDGE-LOGICAL-MOUSE-BOUNDS-CALL
		m3k_bbridge_ui_logical_mouse_bounds(get_hwnd(), max_position);

		imgui_io.AddMousePosEvent(
'@
    $mouseAnchor = Normalize-Text $mouseAnchor
    $mouseReplacement = Normalize-Text $mouseReplacement
    if (!$gui.Contains($mouseAnchor)) {
        throw 'Could not find runtime_gui.cpp AddMousePosEvent input-normalization anchor.'
    }
    $gui = $gui.Replace($mouseAnchor, $mouseReplacement)
    Write-CrlfUtf8 $guiPath $gui
    Write-Host 'Patched runtime_gui.cpp to normalize logical GTA mouse coordinates to ReShade output.'
}

Write-Host 'ReShade 6.8.0 b-bridge input patch applied successfully.' -ForegroundColor Green
