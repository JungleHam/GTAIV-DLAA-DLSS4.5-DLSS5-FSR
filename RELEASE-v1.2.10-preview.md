# GTA IV Scaling v1.2.10 — standalone package preview

This package combines the working 1.2.10 runtime baseline with the project's full Windows installer.

## Included

- Verified b-bridge input relay and the working viewport/presenter runtime.
- DLAA / DLSS and AMD FidelityFX FSR runtime support.
- DLSS 5 feeder and the GPU-aware Neural Rendering updater.
- GPU detection, install / repair, removal, Neural Rendering update, and FusionFix update actions.
- Clean-install foundation setup with official ReShade 6.8.0 Full Add-On Support, LumeniteFX, and the bundled ReShade input-patch DLL.
- SHA-256 verification for the runtime archive, runtime files, ReShade patch, and Neural Rendering downloads.
- Existing bridge/DXVK configuration values, ReShade presets, user shaders, and DLSS/FSR profile settings are preserved where the installer updates project-owned files.

## Keyboard behavior

- Home opens ReShade.
- F11 opens the Steam overlay.
- No End-key remapping or synthetic Home event is included.

## Installation behavior

The installer supports a clean setup and repair/upgrade of an existing GTA IV Scaling installation. On a clean setup, FusionFix may need its first-run launch before the scaling foundation can be installed; the installer explains when to close the game and run setup again.

## Testing status

The runtime baseline is the previously selected working build. The full standalone installer must still receive an in-game installation/repair test before being promoted to a public stable release.