# GTA IV Scaling v1.2.3 — non-16:9 resolution hotfix

Installer/configuration-only update on top of the v1.2.2 DLAA/DLSS + FSR runtime.

## Fixed

- Removes b-bridge 0.1.0's `d3d9.forceAspectRatio = 16:9` from the packaged DXVK configuration.
- Preserves `d3d9.modeCountCompatibility`, which restricts GTA IV's mode list to avoid an overflow.
- On a 1920x1200 (16:10) display, the current desktop mode should once again appear instead of only 1280x720 and 1920x1080. 4:3 and ultrawide use the same fix, subject to validation.
- The full installer also strips any forced-aspect-ratio assignment on install/repair.

## Upgrade from v1.2.2

1. Close GTA IV and NvRemixBridge.exe.
2. Run GTAIV-Scaling-Setup-v1.2.3.exe as administrator.
3. Select your GTA IV directory and Install / Repair.
4. An intact v1.2.2 installation receives a configuration-only upgrade. The current dxvk.conf and version receipt are backed up under _GTAIV_SCALING_PRE123_BACKUP_*, and the version receipt becomes 1.2.3. No scaling DLLs or per-backend settings are overwritten.
5. Restart GTA IV and select the intended mode, first setting Windows to that desktop resolution if necessary.

An incomplete or older install uses the normal full install/repair path with the corrected v1.2.3 runtime configuration.

## Unchanged

- DLAA/DLSS, FSR 3.1.4, RCAS, Neural Rendering and backend switching use the same tested v1.2.2 binaries.
- The Home/Add-ons title still reads GTA IV Scaling 1.2.2 because the feeder binary is unchanged.
- b-bridge deliberately exposes only the desktop mode plus a few standard fallbacks. It does not enumerate every display mode or DSR/DLDSR resolution.

## Verification

Build should verify runtime/feeder hashes, patch and verify DXVK configuration, validate the PowerShell setup script and compile the Inno Setup installer. Real 16:10/4:3/ultrawide hardware testing remains necessary.
