# GTA IV Scaling v1.2.4 — clean-install checksum hotfix

This is a packaging-only fix over v1.2.3. **DLAA, DLSS, FSR and Neural Rendering binaries are unchanged** from the v1.2.2 runtime.

## Fixed
- The v1.2.3 installer could fail on a clean installation with a `dxvk.conf` SHA256 mismatch: it modified the DXVK configuration to remove the forced 16:9 aspect ratio, but the embedded foundation installer still contained an obsolete per-file SHA256.
- The release workflow now computes **all foundation runtime-file hashes** from the runtime that is actually bundled in the setup EXE.
- A regression check verifies each embedded runtime-file checksum against the packaged files before compiling the installer.
- The configuration-only upgrade path accepts intact v1.2.2 **and v1.2.3** installations, retaining their DLAA/DLSS/FSR runtime binaries and per-backend profiles.

## Installation
1. Back up your working GTA IV folder, especially if you use other ASI plugins or LuaModLoader.
2. Launch `GTAIV-Scaling-Setup-v1.2.4.exe` and choose **Install / Repair**.
3. Select the folder containing `GTAIV.exe`.
4. On a clean install, select the official ReShade 6.8.0 Full Add-On Support setup when asked.
5. Run the game and check the Home > Add-ons > GTA IV Scaling controls.

The `d3d9.forceAspectRatio` filter remains removed; `d3d9.modeCountCompatibility` remains enabled.

**Compatibility:** LuaModLoader, Liberty Loadout and custom Lua inventory scripts are not part of the project's CI tests. Test them on a backed-up copy.
