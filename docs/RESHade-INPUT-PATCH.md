# ReShade 6.8.0 b-bridge input patch

## Why it exists

GTA IV owns the game window, while ReShade runs inside `NvRemixBridge.exe`.

Stock ReShade therefore sees a foreign window and cannot normally capture GTA IV keyboard/mouse input.

The project patch reconnects that input path:

```text
GTAIV.exe
  -> b-bridge input forwarding
  -> NvRemixBridge.exe
  -> patched ReShade input handling
```

It also notifies the bridge when the ReShade overlay is open so GTA IV does not consume the same input at the same time.

## Source

The patch is implemented by:

```text
tools/reshade-bbridge-input/apply_patch.ps1
```

It is pinned to ReShade **6.8.0** and should be reviewed before use with a different ReShade version.

## Build

Developer requirements:

- Git
- Python 3
- Visual Studio 2022 / Build Tools with C++

Run:

```text
tools\reshade-bbridge-input\BUILD.bat
```

The result is:

```text
ReShade64-bbridge.dll
```

The runtime/release workflow also builds this patch automatically.

## Installation behavior

The normal user does not run the patch scripts manually.

`GTAIV-DLSS-Setup.exe`:

1. installs the official ReShade 6.8.0 Vulkan layer;
2. preserves the official global ReShade DLL;
3. installs the b-bridge input-patched DLL;
4. applies the required bridge input policies.

Global ReShade location:

```text
C:\ProgramData\ReShade\ReShade64.dll
```

Backup:

```text
C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input
```

Bridge policies:

```ini
client.DirectInput.forward.mousePolicy = 3
client.DirectInput.forward.keyboardPolicy = 3
```

## Overlay shortcut

The installer configures ReShade's `[INPUT] KeyOverlay` as `46,0,0,0` (`VK_DELETE`). This makes **Delete** open the overlay and also updates ReShade's own startup/tutorial prompt, which displays the configured overlay key.

The installer preserves the previous `ReShade.ini` in its pre-install backup before changing this one setting.

## Verification

Launch GTA IV and press **Delete**.

The patch is working when the ReShade overlay opens and accepts mouse/keyboard input. The ReShade prompt should identify **Delete**, not Home.

Useful log:

```text
GTAIV\.trex\ReShade.log
```

The patch only fixes cross-process input. It does not itself provide DLAA, Super Resolution or Neural Rendering.
