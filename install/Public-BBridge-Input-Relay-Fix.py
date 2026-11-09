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

    forward_anchor = "  const bool doForward = msg != WM_INPUT;\n"
    forward_replacement = """  // Keep the alternate Social Club key separate from ReShade's Home shortcut.
  // The End-key hook injects Home with a private dwExtraInfo marker. Let that
  // synthetic Home reach GTA IV/Rockstar, but do not forward it to ReShade.
  const ULONG_PTR messageExtra = static_cast<ULONG_PTR>(GetMessageExtraInfo());
  const bool isSocialClubSyntheticHome =
    messageExtra == static_cast<ULONG_PTR>(0x4D334B53) &&
    (msg == WM_KEYDOWN || msg == WM_KEYUP || msg == WM_SYSKEYDOWN || msg == WM_SYSKEYUP) &&
    wParam == VK_HOME;
  const bool doForward = msg != WM_INPUT && !isSocialClubSyntheticHome;
  if (isSocialClubSyntheticHome) {
    Logger::info("[M3K-SOCIAL-CLUB-ROUTE] Synthetic Home passed to GTA IV but not forwarded to ReShade.");
  }
"""
    if window.count(forward_anchor) != 1:
        raise SystemExit("could not find b-bridge input-forwarding decision")
    window = window.replace(forward_anchor, forward_replacement, 1)

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

    // Optional alternate Social Club shortcut. End injects the Home key
    // while GTA IV is focused; the original End event is swallowed so it
    // cannot also trigger an unrelated in-game action. Home remains native.
    if (key != nullptr && key->vkCode == VK_END &&
        !RemixState::isUIActive() &&
        Config::getOption<bool>("client.SocialClub.endKeyAsHome", false)) {
      INPUT home = {};
      home.type = INPUT_KEYBOARD;
      home.ki.wVk = VK_HOME;
      home.ki.wScan = static_cast<WORD>(MapVirtualKeyW(VK_HOME, MAPVK_VK_TO_VSC));
      home.ki.dwFlags = KEYEVENTF_EXTENDEDKEY |
        ((key->flags & LLKHF_UP) ? KEYEVENTF_KEYUP : 0);
      home.ki.dwExtraInfo = static_cast<ULONG_PTR>(0x4D334B53);

      const UINT sent = SendInput(1, &home, sizeof(INPUT));
      if (sent == 1) {
        Logger::info(format_string(
          "[M3K-SOCIAL-CLUB-END-KEY] End mapped to Home (%s).",
          (key->flags & LLKHF_UP) ? "up" : "down"));
        return 1;
      }

      Logger::warn(format_string(
        "[M3K-SOCIAL-CLUB-END-KEY] SendInput failed while mapping End to Home (error=%lu).",
        GetLastError()));
    }

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


# The alternate Social Club key must work even when b-bridge's optional
# custom-window-hook override is disabled. Install only the low-level keyboard
# hook in that case; do not enable the other custom hooks as a side effect.
if "M3K-SOCIAL-CLUB-HOOK-ALWAYS" not in di:
    old_attach = """static void InputWinHooksAttach() {
  if (!ClientOptions::getOverrideCustomWinHooks()) {
    return;
  }

  assert(gWinHooks.empty());

  auto attachWinHook = [](int idHook, HOOKPROC lpfn) {
    if (HHOOK h = SetWindowsHookEx(idHook, lpfn, nullptr, GetCurrentThreadId())) {
      return std::pair { idHook, h };
    }
    Logger::warn(format_string("SetWindowsHookEx failed with idHook=%d", idHook));
    return std::pair { idHook , static_cast<HHOOK>(nullptr) };
  };

  gWinHooks = {
    attachWinHook(WH_CALLWNDPROC, HookedCallWndProc),
    attachWinHook(WH_GETMESSAGE,  HookedGetMsgProc),
    attachWinHook(WH_KEYBOARD,    HookedKeyboardProc),
    attachWinHook(WH_KEYBOARD_LL, HookedLowLevelKeyboardProc),
  };
}
"""
    new_attach = """static void InputWinHooksAttach() {
  assert(gWinHooks.empty());

  auto attachWinHook = [](int idHook, HOOKPROC lpfn) {
    if (HHOOK h = SetWindowsHookEx(idHook, lpfn, nullptr, GetCurrentThreadId())) {
      return std::pair { idHook, h };
    }
    Logger::warn(format_string("SetWindowsHookEx failed with idHook=%d", idHook));
    return std::pair { idHook , static_cast<HHOOK>(nullptr) };
  };

  if (!ClientOptions::getOverrideCustomWinHooks()) {
    if (Config::getOption<bool>("client.SocialClub.endKeyAsHome", false)) {
      gWinHooks = {
        attachWinHook(WH_KEYBOARD_LL, HookedLowLevelKeyboardProc),
      };
      Logger::info("[M3K-SOCIAL-CLUB-HOOK-ALWAYS] Installed the low-level keyboard hook for the optional End-to-Home shortcut.");
    }
    return;
  }

  gWinHooks = {
    attachWinHook(WH_CALLWNDPROC, HookedCallWndProc),
    attachWinHook(WH_GETMESSAGE,  HookedGetMsgProc),
    attachWinHook(WH_KEYBOARD,    HookedKeyboardProc),
    attachWinHook(WH_KEYBOARD_LL, HookedLowLevelKeyboardProc),
  };
}
"""
    if di.count(old_attach) != 1:
        raise SystemExit("could not find InputWinHooksAttach block")
    di = di.replace(old_attach, new_attach, 1)
    di_path.write_text(di, encoding="utf-8", newline="\n")


window_check = window_path.read_text(encoding="utf-8")
di_check = di_path.read_text(encoding="utf-8")
for marker, source in (
    ("M3K-BBRIDGE-RELAY-ACK-HOOK", window_check),
    ("M3K-SOCIAL-CLUB-ROUTE", window_check),
    ("M3K-BRIDGE-INPUT-TRACE", di_check),
    ("M3K-STEAM-INPUT", di_check),
    ("M3K-SOCIAL-CLUB-END-KEY", di_check),
    ("M3K-SOCIAL-CLUB-HOOK-ALWAYS", di_check),
):
    if marker not in source:
        raise SystemExit(f"verification failed: {marker}")

print("Applied b-bridge relay ACK hooks for all game window threads and Home/F11 input tracing")
