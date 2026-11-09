# GTA IV Scaling v1.2.10 — standalone release

v1.2.10 packages the project's current DLAA/DLSS, FSR and DLSS Neural Rendering runtime as one complete Windows installer.

## Why this release exists

Earlier setups required more manual assembly and depended on an existing Scaling installation or separately prepared runtime files. v1.2.10 brings the runtime, ReShade input patch, installer actions and dependency handling together in one standalone package. It can install on a clean GTA IV setup, repair/update an existing installation, update the Neural Rendering DLL independently, manage FusionFix, and remove the project cleanly.

## Fixed in v1.2.10

- **ReShade / Rockstar overlay hotkey conflict:** ReShade now opens with **Delete** instead of Home. This stops ReShade from taking the Home key, leaving Home available for the Rockstar Games overlay.
- **Consistent shortcut instructions:** The installer introduction, completion message and ReShade startup prompt all identify **Delete** as the ReShade key.
- **No End-key experiment:** The abandoned End-to-Home Social Club remapping is not included. F11 remains unchanged for the Steam overlay.
- **Standalone packaging and integrity checks:** The installer bundles the matching runtime and ReShade input-patch files and verifies their SHA-256 hashes. Clean installs no longer depend on downloading an earlier GTA IV Scaling installer.

## Included

- Native rendering, NVIDIA DLAA / DLSS and AMD FidelityFX FSR in one runtime.
- DLSS custom render scale, NVIDIA sharpening and temporal controls.
- FSR scaling and independent RCAS sharpening.
- Optional DLSS 5 Neural Rendering controls and GPU-aware NR DLL updater for supported RTX generations.
- GPU-aware in-game backend visibility.
- Unified Install / Repair, NR-only update, FusionFix-only update, and uninstall options.
- Runtime backup and preservation of existing ReShade presets and user configuration where supported.
- The established b-bridge input relay and viewport/presenter runtime.

## Known issue — ReShade mouse bounds (not fixed in v1.2.10)

When DLSS/FSR render scaling is active below native resolution, the ReShade overlay's interactive mouse area can remain limited to the internal render resolution instead of the full display/output resolution. For example, with a 1440p display and a lower internal render resolution, the cursor may be restricted to a smaller area in the upper-left portion of the overlay.

This issue is still present in v1.2.10. It is documented intentionally and is the next planned input/UI fix. Do not treat the cursor-boundary issue as resolved by this release.

## Installation

1. Close GTA IV and NvRemixBridge.exe.
2. Download `GTAIV-Scaling-Setup-v1.2.10.exe` from the Assets section below.
3. Run the installer as Administrator and select the folder containing `GTAIV.exe`.
4. Choose **Install / Repair** and follow the prompts. On a clean setup, provide the official ReShade 6.8.0 Full Add-On Support installer when requested.
5. Launch GTA IV. Press **Delete** to open ReShade, then open **Add-ons → GTA IV Scaling**.

The installer is intended for Windows 10/11 x64 and GTA IV: Complete Edition. The Steam build is the primary tested configuration; other launcher builds may require additional compatibility testing.
