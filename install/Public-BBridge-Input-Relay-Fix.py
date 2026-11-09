#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Input-Relay-Fix.py <b-bridge-root>")

root = Path(sys.argv[1])
window_path = root / "src" / "client" / "window.cpp"
di_path = root / "src" / "client" / "di_hook.cpp"

if not window_path.is_file() or not di_path.is_file():
    raise SystemExit("missing b-bridge window.cpp or di_hook.cpp")

window = window_path.read_text(encoding="utf-8")
window_marker = "M3K-BBRIDGE-RELAY-ACK-HOOK"
if window_marker not in window:
    include_anchor = "#include <unordered_map>"
    if include_anchor not in window:
        raise SystemExit("could not find window.cpp unordered_map include")
    window = window.replace(
        include_anchor,
        include_anchor + "\n#include <algorithm>\n#include <vector>",
        1,
    )

    anchor = "bool g_bActivateProcessed = false;\n"
    helper = r'''
// M3K-BBRIDGE-RELAY-ACK-HOOK
// ReShade runs in NvRemixBridge.exe, while the b-bridge client and its
// MessageChannelClient run in GTAIV.exe. Do not treat a successful
// SendMessageTimeout as proof that the registered handshake was handled.
// A thread-specific CALLWNDPROC hook observes the handshake even if another
// component changes a window's WndProc chain, and explicitly ACKs the worker.
std::unordered_map<DWORD, HHOOK> g_relayHandshakeHooks;
UINT g_relayHandshakeMsg = 0;
UINT g_relayAckMsg = 0;
UINT g_relayUiActiveMsg = 0;

struct RelayHookThreadList
{
  DWORD processId;
  std::vector<DWORD> threadIds;
};

static void addRelayHookThread(RelayHookThreadList &list, HWND hwnd)
{
  if (hwnd == nullptr || !IsWindow(hwnd))
    return;

  DWORD processId = 0;
  const DWORD threadId = GetWindowThreadProcessId(hwnd, &processId);
  if (processId != list.processId || threadId == 0)
    return;

  if (std::find(list.threadIds.begin(), list.threadIds.end(), threadId) == list.threadIds.end())
    list.threadIds.push_back(threadId);
}

static BOOL CALLBACK enumRelayChildWindows(HWND hwnd, LPARAM parameter)
{
  auto *list = reinterpret_cast<RelayHookThreadList *>(parameter);
  addRelayHookThread(*list, hwnd);
  return TRUE;
}

static BOOL CALLBACK enumRelayTopWindows(HWND hwnd, LPARAM parameter)
{
  auto *list = reinterpret_cast<RelayHookThreadList *>(parameter);
  addRelayHookThread(*list, hwnd);
  EnumChildWindows(hwnd, enumRelayChildWindows, parameter);
  return TRUE;
}

static LRESULT CALLBACK RelayHandshakeHookProc(int nCode, WPARAM wParam, LPARAM lParam)
{
  if (nCode >= 0 && lParam != 0 && gpRemixMessageChannel)
  {
    const CWPSTRUCT *call = reinterpret_cast<const CWPSTRUCT *>(lParam);

    if (call->message == g_relayHandshakeMsg)
    {
      if (gpRemixMessageChannel->onMessage(
            call->message,
            static_cast<uint32_t>(call->wParam),
            static_cast<uint32_t>(call->lParam)))
      {
        if (g_relayAckMsg == 0)
          g_relayAckMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_INPUT_RELAY_ACK_MSG");

        const BOOL posted = g_relayAckMsg != 0 && PostThreadMessageW(
          static_cast<DWORD>(call->wParam), g_relayAckMsg, 1, 0);

        Logger::info(format_string(
          "[M3K-BBRIDGE-RELAY-ACK] WH_CALLWNDPROC hwnd=%p worker=%lu posted=%d",
          call->hwnd, static_cast<unsigned long>(call->wParam), posted ? 1 : 0));
      }
    }
    else if (call->message == g_relayUiActiveMsg)
    {
      const bool uiWasActive = RemixState::isUIActive();
      gpRemixMessageChannel->onMessage(
        call->message,
        static_cast<uint32_t>(call->wParam),
        static_cast<uint32_t>(call->lParam));

      // This hook may be the only receiver if another component replaced
      // RemixWndProc. Preserve the same activation side effects normally
      // performed by remixMsg so the game does not keep stale modifier state.
      if (!uiWasActive && RemixState::isUIActive())
      {
        auto unstick = [hWnd = call->hwnd](uint32_t vk) {
          if (g_gameWndProc)
            CallWindowProc(g_gameWndProc, hWnd, WM_KEYUP, vk,
              ((KF_REPEAT + KF_UP + MapVirtualKeyA(vk, MAPVK_VK_TO_VSC)) << 16) + 1);
        };

        unstick(VK_CONTROL);
        unstick(VK_SHIFT);
        unstick(VK_INSERT);
        InputWinHooksReattach();
        Logger::info("[M3K-BBRIDGE-RELAY-ACK-HOOK] UI-active transition handled by CALLWNDPROC hook.");
      }
    }
  }

  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

static void ensureRelayHandshakeHooksForProcess(HWND hwnd)
{
  DWORD processId = 0;
  const DWORD windowThread = GetWindowThreadProcessId(hwnd, &processId);
  if (processId != GetCurrentProcessId() || windowThread == 0)
    return;

  g_relayHandshakeMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG");
  g_relayAckMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_INPUT_RELAY_ACK_MSG");
  g_relayUiActiveMsg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");

  RelayHookThreadList list = { processId, {} };
  addRelayHookThread(list, hwnd);
  EnumWindows(enumRelayTopWindows, reinterpret_cast<LPARAM>(&list));

  for (const DWORD threadId : list.threadIds)
  {
    if (g_relayHandshakeHooks.find(threadId) != g_relayHandshakeHooks.end())
      continue;

    // A thread-specific hook in this process can use a null module handle.
    HHOOK hook = SetWindowsHookExA(
      WH_CALLWNDPROC, RelayHandshakeHookProc, nullptr, threadId);

    if (hook)
    {
      g_relayHandshakeHooks.emplace(threadId, hook);
      Logger::info(format_string(
        "[M3K-BBRIDGE-RELAY-ACK-HOOK] WH_CALLWNDPROC hook installed thread=%lu",
        static_cast<unsigned long>(threadId)));
    }
    else
    {
      Logger::warn(format_string(
        "[M3K-BBRIDGE-RELAY-ACK] WH_CALLWNDPROC hook install failed thread=%lu error=%lu",
        static_cast<unsigned long>(threadId), GetLastError()));
    }
  }
}

static void removeRelayHandshakeHooks()
{
  for (const auto &entry : g_relayHandshakeHooks)
    UnhookWindowsHookEx(entry.second);

  g_relayHandshakeHooks.clear();
}
'''
    if window.count(anchor) != 1:
        raise SystemExit("could not find window.cpp global-state anchor")
    window = window.replace(anchor, anchor + helper, 1)

    set_anchor = "  DInputSetDefaultWindow(hwnd);\n"
    set_replacement = set_anchor + "  ensureRelayHandshakeHooksForProcess(hwnd);\n"
    if window.count(set_anchor) != 1:
        raise SystemExit("could not find WndProc::set DirectInput anchor")
    window = window.replace(set_anchor, set_replacement, 1)

    terminate_anchor = "bool terminate() {\n"
    terminate_replacement = terminate_anchor + "  removeRelayHandshakeHooks();\n"
    if window.count(terminate_anchor) != 1:
        raise SystemExit("could not find WndProc::terminate anchor")
    window = window.replace(terminate_anchor, terminate_replacement, 1)

    msg_anchor = "  if (gpRemixMessageChannel->onMessage(msg, wParam, lParam)) {\n"
    msg_replacement = """  if (gpRemixMessageChannel->onMessage(msg, wParam, lParam)) {
    if (msg == g_relayHandshakeMsg) {
      if (g_relayAckMsg == 0)
        g_relayAckMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_INPUT_RELAY_ACK_MSG");
      const BOOL posted = g_relayAckMsg != 0 && PostThreadMessageW(
        static_cast<DWORD>(wParam), g_relayAckMsg, 1, 0);
      Logger::info(format_string(
        "[M3K-BBRIDGE-RELAY-ACK] RemixWndProc hwnd=%p worker=%lu posted=%d",
        hWnd, static_cast<unsigned long>(wParam), posted ? 1 : 0));
    }
"""
    if window.count(msg_anchor) != 1:
        raise SystemExit("could not find remixMsg renderer-channel handler")
    window = window.replace(msg_anchor, msg_replacement, 1)

    send_anchor = """  if (doForward) {
    gpRemixMessageChannel->send(msg, wParam, lParam);
  }
"""
    send_replacement = """  if (doForward) {
    const bool relaySent = gpRemixMessageChannel->send(msg, wParam, lParam);
    if ((msg == WM_KEYDOWN || msg == WM_KEYUP) &&
        (wParam == VK_HOME || wParam == VK_F11)) {
      Logger::info(format_string(
        "[M3K-BBRIDGE-RELAY-KEY] hwnd=%p msg=0x%X vk=0x%02X ready=%d sent=%d ui=%d",
        hWnd, msg, static_cast<unsigned int>(wParam),
        gpRemixMessageChannel->canSend() ? 1 : 0,
        relaySent ? 1 : 0, RemixState::isUIActive() ? 1 : 0));
    }
  }
"""
    if window.count(send_anchor) != 1:
        raise SystemExit("could not find remixMsg input-forwarding block")
    window = window.replace(send_anchor, send_replacement, 1)

    window_path.write_text(window, encoding="utf-8", newline="\n")

di = di_path.read_text(encoding="utf-8")
if "M3K-BRIDGE-INPUT-TRACE" not in di:
    old = """  static void forwardMessage(const WndMsg& wm) {
    const DeviceType devType =
      (wm.msg >= WM_MOUSEFIRST && wm.msg <= WM_MOUSELAST) ? DeviceType::Mouse : DeviceType::Keyboard;
    // Bail when input is not exclusive OR policy says no
    if(!s_bIsExclusive[devType] || !evaluatePolicy(devType)) {
      return;
    }
    WndProc::invokeRemixWndProc(wm.msg, wm.wParam, wm.lParam);
  }
"""
    new = """  static void forwardMessage(const WndMsg& wm) {
    const DeviceType devType =
      (wm.msg >= WM_MOUSEFIRST && wm.msg <= WM_MOUSELAST) ? DeviceType::Mouse : DeviceType::Keyboard;
    const bool exclusive = s_bIsExclusive[devType];
    const bool policyAllowed = evaluatePolicy(devType);
    const bool traceKey = devType == Keyboard &&
      (wm.msg == WM_KEYDOWN || wm.msg == WM_KEYUP) &&
      (wm.wParam == VK_HOME || wm.wParam == VK_F11);

    if (!exclusive || !policyAllowed) {
      if (traceKey) {
        Logger::info(format_string(
          "[M3K-BRIDGE-INPUT-TRACE] VK=0x%02X not forwarded exclusive=%d policy=%d ui=%d",
          static_cast<unsigned int>(wm.wParam), exclusive ? 1 : 0,
          static_cast<int>(s_forwardPolicies[devType]),
          RemixState::isUIActive() ? 1 : 0));
      }
      return;
    }

    if (traceKey) {
      Logger::info(format_string(
        "[M3K-BRIDGE-INPUT-TRACE] VK=0x%02X forwarding exclusive=%d policy=%d ui=%d",
        static_cast<unsigned int>(wm.wParam), exclusive ? 1 : 0,
        static_cast<int>(s_forwardPolicies[devType]),
        RemixState::isUIActive() ? 1 : 0));
    }

    WndProc::invokeRemixWndProc(wm.msg, wm.wParam, wm.lParam);
  }
"""
    if di.count(old) != 1:
        raise SystemExit("could not find DirectInput forwardMessage block")
    di = di.replace(old, new, 1)

    old_hook = """static LRESULT CALLBACK HookedLowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  LogStaticFunctionCall();

  if (nCode >= 0) {
    if (RemixState::isUIActive()) {
      return 0;
    }
  }

  return CallNextHookEx(accessWinHook(WH_KEYBOARD_LL), nCode, wParam, lParam);
}
"""
    new_hook = """static LRESULT CALLBACK HookedLowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  LogStaticFunctionCall();

  if (nCode >= 0) {
    const KBDLLHOOKSTRUCT *key = reinterpret_cast<const KBDLLHOOKSTRUCT *>(lParam);
    if (key != nullptr && key->vkCode == VK_F11) {
      Logger::info(format_string(
        "[M3K-STEAM-INPUT] low-level F11 message=0x%X ui=%d",
        static_cast<unsigned int>(wParam), RemixState::isUIActive() ? 1 : 0));
    }

    if (RemixState::isUIActive()) {
      return 0;
    }
  }

  return CallNextHookEx(accessWinHook(WH_KEYBOARD_LL), nCode, wParam, lParam);
}
"""
    if di.count(old_hook) != 1:
        raise SystemExit("could not find low-level keyboard hook block")
    di = di.replace(old_hook, new_hook, 1)

    di_path.write_text(di, encoding="utf-8", newline="\n")

# Keep the DirectInput mouse clamp synchronized with the live game client area.
# b-bridge can attach before GTA IV finishes its initial window sizing. The
# original code sampled GetWindowRect only when the window was first attached
# or a keyboard state changed, so a stale startup size could permanently clamp
# the ReShade cursor until a display-mode change caused another refresh.
if "M3K-BRIDGE-MOUSE-BOUNDS-REFRESH" not in di:
    old_size = """  static void updateWindowSize() {
    RECT rect;
    ::GetWindowRect(s_hwnd, &rect);

    // Only accept reasonable window extents.
    // NOTE: A game overlay may setup a zero-sized DirectInput window and make
    // cursor position clamping code produce wrong results.
    if (rect.right - rect.left > 16) {
      s_windowWidth = rect.right - rect.left;
    }

    if (rect.bottom - rect.top > 16) {
      s_windowHeight = rect.bottom - rect.top;
    }
  }
"""
    new_size = """  static void updateWindowSize() {
    // M3K-BRIDGE-MOUSE-BOUNDS-REFRESH
    // Mouse messages forwarded to ReShade use client coordinates, so clamp
    // against the live client area rather than the outer window rectangle.
    if (s_hwnd == nullptr || !IsWindow(s_hwnd)) {
      return;
    }

    RECT rect = {};
    if (!::GetClientRect(s_hwnd, &rect)) {
      return;
    }

    const LONG width = rect.right - rect.left;
    const LONG height = rect.bottom - rect.top;

    // Preserve the last valid dimensions while minimized or during a mode switch.
    if (width > 16 && height > 16) {
      if (width != s_windowWidth || height != s_windowHeight) {
        Logger::info(format_string(
          "[M3K-BRIDGE-MOUSE-BOUNDS-REFRESH] client=%ldx%ld hwnd=%p previous=%ldx%ld",
          width, height, s_hwnd, s_windowWidth, s_windowHeight));
      }

      s_windowWidth = width;
      s_windowHeight = height;
    }
  }
"""
    if di.count(old_size) != 1:
        raise SystemExit("could not find original DirectInput window-size function")
    di = di.replace(old_size, new_size, 1)

    old_mouse = """  template<typename T>
  static void updateMouseState(const T* state, bool isAbsoluteAxis) {
    if (isAbsoluteAxis) {
"""
    new_mouse = """  template<typename T>
  static void updateMouseState(const T* state, bool isAbsoluteAxis) {
    // M3K-BRIDGE-MOUSE-BOUNDS-REFRESH-CALL
    // Refresh before clamping every mouse sample, not only on keyboard events.
    updateWindowSize();

    if (isAbsoluteAxis) {
"""
    if di.count(old_mouse) != 1:
        raise SystemExit("could not find DirectInput mouse-state function")
    di = di.replace(old_mouse, new_mouse, 1)

    di_path.write_text(di, encoding="utf-8", newline="\n")

window_check = window_path.read_text(encoding="utf-8")
di_check = di_path.read_text(encoding="utf-8")
for marker, source in (
    ("M3K-BBRIDGE-RELAY-ACK-HOOK", window_check),
    ("M3K-BRIDGE-INPUT-TRACE", di_check),
    ("M3K-BRIDGE-MOUSE-BOUNDS-REFRESH", di_check),
    ("M3K-BRIDGE-MOUSE-BOUNDS-REFRESH-CALL", di_check),
    ("M3K-STEAM-INPUT", di_check),
):
    if marker not in source:
        raise SystemExit(f"verification failed: {marker}")

print("Applied b-bridge relay ACK hooks for all game window threads and Home/F11 input tracing")
