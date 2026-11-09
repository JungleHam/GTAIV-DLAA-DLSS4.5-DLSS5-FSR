# ReShade b-bridge input patch

Normal users do not need to run these files manually. `GTAIV-DLSS-Setup.exe` installs the release patch automatically.

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design.

## Developer build

1. Run **`BUILD.bat`**.
2. Wait for `BUILD SUCCESS - PATCH MARKER VERIFIED`.
3. The result is `ReShade64-bbridge.dll`.

## Manual developer install

If you are testing the patch outside the main installer:

1. Close GTA IV and `NvRemixBridge.exe`.
2. Run **`INSTALL.bat`** as Administrator.
3. Select the GTA IV folder containing `GTAIV.exe`.
4. Launch GTA IV and press **Delete**.
5. Confirm the ReShade overlay accepts mouse and keyboard input.

Useful files:

```text
GTAIV\.trex\bridge.conf
GTAIV\.trex\ReShade.log
```

## Rollback

Run **`RESTORE_ORIGINAL.bat`** to restore the official ReShade DLL backup.

The local `ReShade64-bbridge.dll` build output and cloned `reshade-src/` tree are ignored by Git.
