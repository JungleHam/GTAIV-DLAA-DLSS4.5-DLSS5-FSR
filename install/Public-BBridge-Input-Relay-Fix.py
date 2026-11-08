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
    anchor = "bool g_bActivateProcessed = false;\n"
    helper = r'''
// M3K-BBRIDGE-RELAY-ACK-HOOK
// ReShade lives in NvRemixBridge.exe, while this WndProc lives in GTAIV.exe.
// A SendMessageTimeout success alone does NOT prove that RemixWndProc handled
// the registered handshake. Keep a thread-specific CALLWNDPROC hook as a
// fallback so the relay still works if another component changes the HWND's
// WndProc chain or ReShade targets a sibling/child HWND on the same UI thread.
HHOOK g_relayHandshakeHook = nullptr;
DWORD g_relayHandshakeHookThread = 0;
UINT g_relayHandshakeMsg = 0;
UINT g_relayAckMsg = 0;
UINT g_relayUiActiveMsg = 0;

static void acknowledgeRelayThread(HWND hwnd, WPARAM threadId, const char *source)
{
  if (g_relayAckMsg == 0)
    g_relayAckMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_INPUT_RELAY_ACK_MSG");

  if (g_relayAckMsg == 0 || threadId == 0)
    return;

  const BOOL posted = PostThreadMessageW(
    static_cast<DWORD>(threadId), g_relayAckMsg, 1, 0);

  Logger::info(format_string(
    "[M3K-BBRIDGE-RELAY-ACK] source=%s hwnd=%p worker=%lu posted=%d",
    source, hwnd, static_cast<unsigned long>(threadId), posted ? 1 : 0));
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
        acknowledgeRelayThread(call->hwnd, call->wParam, "WH_CALLWNDPROC");
      }
    }
    else if (call->message == g_relayUiActiveMsg)
    {
      gpRemixMessageChannel->onMessage(
        call->message,
        static_cast<uint32_t>(call->wParam),
        static_cast<uint32_t>(call->lParam));
    }
  }

  return CallNextHookEx(g_relayHandshakeHook, nCode, wParam, lParam);
}

static void ensureRelayHandshakeHook(HWND hwnd)
{
  DWORD processId = 0;
  const DWORD threadId = GetWindowThreadProcessId(hwnd, &processId);
  if (processId != GetCurrentProcessId() || threadId == 0)
    return;

  g_relayHandshakeMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG");
  g_relayAckMsg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_INPUT_RELAY_ACK_MSG");
  g_relayUiActiveMsg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");

  if (g_relayHandshakeHook && g_relayHandshakeHookThread == threadId)
    return;

  if (g_relayHandshakeHook)
  {
    UnhookWindowsHookEx(g_relayHandshakeHook);
    g_relayHandshakeHook = nullptr;
    g_relayHandshakeHookThread = 0;
  }

  // A thread-specific hook in this process can use a null module handle.
  g_relayHandshakeHook = SetWindowsHookExA(
    WH_CALLWNDPROC, RelayHandshakeHookProc, nullptr, threadId);

  if (g_relayHandshakeHook)
  {
    g_relayHandshakeHookThread = threadId;
    Logger::info(format_string(
      "[M3K-BBRIDGE-RELAY-ACK] WH_CALLWNDPROC hook installed hwnd=%p thread=%lu",
      hwnd, static_cast<unsigned long>(threadId)));
  }
  else
  {
    Logger::warn(format_string(
      "[M3K-BBRIDGE-RELAY-ACK] WH_CALLWNDPROC hook install failed hwnd=%p thread=%lu error=%lu",
      hwnd, static_cast<unsigned long>(threadId), GetLastError()));
  }
}

static void removeRelayHandshakeHook()
{
  if (g_relayHandshakeHook)
    UnhookWindowsHookEx(g_relayHandshakeHook);

  g_relayHandshakeHook = nullptr;
  g_relayHandshakeHookThread = 0;
}
'''
    if window.count(anchor) != 1:
        raise SystemExit("could not find window.cpp global-state anchor")
    window = window.replace(anchor, anchor + helper, 1)

    set_anchor = "  DInputSetDefaultWindow(hwnd);\n"
    set_replacement = set_anchor + "  ensureRelayHandshakeHook(hwnd);\n"
    if window.count(set_anchor) != 1:
        raise SystemExit("could not find WndProc::set DirectInput anchor")
    window = window.replace(set_anchor, set_replacement, 1)

    terminate_anchor = "bool terminate() {\n"
    terminate_replacement = terminate_anchor + "  removeRelayHandshakeHook();\n"
    if window.count(terminate_anchor) != 1:
        raise SystemExit("could not find WndProc::terminate anchor")
    window = window.replace(terminate_anchor, terminate_replacement, 1)

    # Keep the ordinary WndProc path as a second way to acknowledge the relay.
    msg_anchor = "  if (gpRemixMessageChannel->onMessage(msg, wParam, lParam)) {\n"
    msg_replacement = """  if (gpRemixMessageChannel->onMessage(msg, wParam, lParam)) {
    if (msg == g_relayHandshakeMsg)
      acknowledgeRelayThread(hWnd, wParam, "RemixWndProc");
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
di_marker = "M3K-BRIDGE-INPUT-TRACE"
if di_marker not in di:
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

window_check = window_path.read_text(encoding="utf-8")
di_check = di_path.read_text(encoding="utf-8")
for marker, source in (
    ("M3K-BBRIDGE-RELAY-ACK-HOOK", window_check),
    ("M3K-BRIDGE-INPUT-TRACE", di_check),
    ("M3K-STEAM-INPUT", di_check),
):
    if marker not in source:
        raise SystemExit(f"verification failed: {marker}")

print("Applied b-bridge relay handshake acknowledgement, thread hook, and Home/F11 input tracing")
