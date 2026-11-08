# GTA IV Scaling v1.2.9 — Rockstar Social Club overlay compatibility

**A targeted compatibility update for the November 3, 2026 Rockstar Games Launcher / Social Club overlay change.**

## What changed
- Adds the official upstream GTA IV RTX compatibility mod **1.7.3** file `a_gta4-rtx.asi`.
- The upstream fix refuses Direct3D devices created for non-game windows, preventing the temporary Social Club overlay device from replacing the game's device references.
- Existing verified v1.2.8 installations receive the compatibility ASI update without reinstalling or replacing the scaling runtime.
- Existing `a_gta4-rtx.asi` is backed up before replacement. The original is restored on uninstall if the installed 1.7.3 file has not been modified. If a user already has the exact 1.7.3 ASI, the installer leaves it unmanaged.
- The uninstaller snapshots the ASI before restoring the original, so failed uninstalls can roll back safely.

## Preserved components
The following v1.2.8 components remain pinned and unchanged:
- Custom b-bridge `d3d9.dll` SHA-256: `B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF`
- Bridge mask: `clientRedundantBypassMask=1032192`
- ReShade b-bridge input patch
- DLSS 5 feeder, DXVK presenter, DLSS / FSR runtime, and Neural Rendering updater
- Existing FusionFix and user mods

## Upstream provenance
- Project: [xoxor4d/gta4-rtx](https://github.com/xoxor4d/gta4-rtx)
- Release: [v1.7.3](https://github.com/xoxor4d/gta4-rtx/releases/tag/v1.7.3)
- Functional fix commit: [19f1b749](https://github.com/xoxor4d/gta4-rtx/commit/19f1b7494783ce1cc67a3ca41a805154bd9b87c0)
- Upstream compatibility archive SHA-256: `0482092C0A64083FC5E4233E92656210D71802D2C2D1AAEF83BB01E97D6C778F`
- The build extracts only `GTAIV-Remix-CompatibilityMod/a_gta4-rtx.asi` from that verified archive. The 209 MB archive itself is not redistributed.

## Important testing note
This is a targeted port of the upstream Direct3D device-selection fix. The original changelog describes a startup crash caused by Social Club's temporary device; it does not explicitly promise to fix every Steam or ReShade hotkey issue. After installing, test both the Steam overlay and ReShade Home menu. If either remains broken, the next step is to inspect the new ASI's runtime log and input hook interaction rather than replace the pinned rendering stack.
