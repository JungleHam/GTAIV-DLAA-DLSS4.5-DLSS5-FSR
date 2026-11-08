#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-DirectInput-ScanCode-Fix.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "client" / "di_hook.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge source: {source}")

text = source.read_text(encoding="utf-8")
marker = "M3K-BRIDGE-DIK-EXTENDED-KEYS"
if marker in text:
    print("M3K DirectInput extended-key fix already present")
    raise SystemExit(0)

old = """        UINT vk = 0;

        switch (vsc) {
        case 210:
          // No translation
          vk = VK_INSERT;
          break;
        default:
          vk = MapVirtualKeyExA(vsc, MAPVK_VSC_TO_VK, NULL);
        }

        if (0 == vk) {
          Logger::warn(format_string("DirectInput: unable to translate VSC: %d", vsc));
          continue;
        }

        WndMsg wm { s_hwnd };
        wm.msg = (KS[vsc] & 0x80) ? WM_KEYDOWN : WM_KEYUP;
        wm.wParam = vk;
        forwardMessage(wm);
"""
new = """        // M3K-BRIDGE-DIK-EXTENDED-KEYS:
        // DirectInput's DIK_* values for E0 keys (for example DIK_HOME=0xC7)
        // are not Win32 hardware scan codes. Passing them straight to
        // MapVirtualKeyExA loses the E0 prefix, so navigation keys cannot be
        // translated and ReShade never receives its Home toggle.
        UINT vk = 0;
        UINT winScanCode = vsc;
        bool extended = false;

        switch (vsc) {
        case DIK_NUMPADENTER: vk = VK_RETURN;   winScanCode = 0x1C; extended = true; break;
        case DIK_RCONTROL:    vk = VK_RCONTROL; winScanCode = 0x1D; extended = true; break;
        case DIK_DIVIDE:      vk = VK_DIVIDE;   winScanCode = 0x35; extended = true; break;
        case DIK_SYSRQ:       vk = VK_SNAPSHOT; winScanCode = 0x37; extended = true; break;
        case DIK_RMENU:       vk = VK_RMENU;    winScanCode = 0x38; extended = true; break;
        case DIK_PAUSE:       vk = VK_PAUSE;    winScanCode = 0x45; break;
        case DIK_HOME:        vk = VK_HOME;     winScanCode = 0x47; extended = true; break;
        case DIK_UP:          vk = VK_UP;       winScanCode = 0x48; extended = true; break;
        case DIK_PRIOR:       vk = VK_PRIOR;    winScanCode = 0x49; extended = true; break;
        case DIK_LEFT:        vk = VK_LEFT;     winScanCode = 0x4B; extended = true; break;
        case DIK_RIGHT:       vk = VK_RIGHT;    winScanCode = 0x4D; extended = true; break;
        case DIK_END:         vk = VK_END;      winScanCode = 0x4F; extended = true; break;
        case DIK_DOWN:        vk = VK_DOWN;     winScanCode = 0x50; extended = true; break;
        case DIK_NEXT:        vk = VK_NEXT;     winScanCode = 0x51; extended = true; break;
        case DIK_INSERT:      vk = VK_INSERT;   winScanCode = 0x52; extended = true; break;
        case DIK_DELETE:      vk = VK_DELETE;   winScanCode = 0x53; extended = true; break;
        case DIK_LWIN:        vk = VK_LWIN;     winScanCode = 0x5B; extended = true; break;
        case DIK_RWIN:        vk = VK_RWIN;     winScanCode = 0x5C; extended = true; break;
        case DIK_APPS:        vk = VK_APPS;     winScanCode = 0x5D; extended = true; break;
        default:
          vk = MapVirtualKeyExA(vsc, MAPVK_VSC_TO_VK, NULL);
          break;
        }

        if (0 == vk) {
          Logger::warn(format_string("DirectInput: unable to translate VSC: %d", vsc));
          // Remember the state even for an unsupported key; otherwise the same
          // untranslatable held key produces one warning per DirectInput poll.
          s_KS[vsc] = KS[vsc];
          continue;
        }

        const bool keyDown = (KS[vsc] & 0x80) != 0;
        const bool wasDown = (s_KS[vsc] & 0x80) != 0;
        const WORD keyFlags = static_cast<WORD>(
          (winScanCode & 0xFFu) |
          (extended ? 0x0100u : 0u) |
          (wasDown ? 0x4000u : 0u) |
          (!keyDown ? 0x8000u : 0u));

        WndMsg wm { s_hwnd };
        wm.msg = keyDown ? WM_KEYDOWN : WM_KEYUP;
        wm.wParam = vk;
        wm.lParam = MAKELPARAM(1, keyFlags);
        forwardMessage(wm);

        if (extended) {
          Logger::info(format_string(
            "[M3K-DI-KEY] DIK 0x%02X -> VK 0x%02X (scan=0x%02X E0)",
            vsc, vk, winScanCode));
        }
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f"DirectInput translation block count={count}, expected 1")
text = text.replace(old, new, 1)

old_ascii = "          if (1 == ToAscii(vk, vsc, KS, ascii, 0)) {"
new_ascii = "          if (!extended && 1 == ToAscii(vk, winScanCode, KS, ascii, 0)) {"
if text.count(old_ascii) != 1:
    raise SystemExit(f"ToAscii call count={text.count(old_ascii)}, expected 1")
text = text.replace(old_ascii, new_ascii, 1)

for required in (
    "case DIK_HOME:        vk = VK_HOME",
    "case DIK_UP:          vk = VK_UP",
    "wm.lParam = MAKELPARAM(1, keyFlags);",
    "[M3K-DI-KEY]",
    "s_KS[vsc] = KS[vsc];",
):
    if required not in text:
        raise SystemExit(f"DirectInput fix verification failed: {required}")

source.write_text(text, encoding="utf-8", newline="\n")
print("Applied M3K DirectInput DIK-to-Win32 extended-key mapping")
