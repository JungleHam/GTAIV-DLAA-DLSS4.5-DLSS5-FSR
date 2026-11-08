# GTA IV Scaling v1.2.9 — corrected installer maintenance build

**This corrected build removes an incompatible RTX Remix component that was mistakenly included in an earlier v1.2.9 test artifact.**

## Important correction
The previous v1.2.9 candidate bundled only `a_gta4-rtx.asi` from the GTA IV RTX Remix Compatibility Mod 1.7.3. That ASI is not a standalone Social Club hotkey patch: the upstream project is specifically built for NVIDIA RTX Remix and requires its custom Remix Runtime and supporting assets. The incomplete ASI-only integration can initialize RTX Remix modules without the required runtime/assets and crash during loading.

**Do not use the earlier v1.2.9 test artifact that contains `a_gta4-rtx.asi`.** This corrected build does not install that ASI and does not overwrite the existing scaling renderer.

## Migration from the earlier v1.2.9 test build
If the installation receipt records that the previous installer managed `a_gta4-rtx.asi`, the corrected v1.2.9 repair path:
- Verifies the current ASI against the recorded SHA-256 before touching it.
- Restores the pre-install ASI from its verified backup if one existed.
- Otherwise removes only the exact ASI that the previous installer placed.
- Preserves a changed or user-replaced ASI rather than overwriting it.
- Removes the obsolete ASI ownership entries from the install receipt.

The uninstaller also restores the previous ASI when one existed, or removes the installer-managed ASI when no original existed.

## Preserved components
- Custom b-bridge `d3d9.dll` SHA-256: `B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF`
- Bridge mask: `clientRedundantBypassMask=1032192`
- ReShade b-bridge input patch
- DLSS 5 feeder, DXVK presenter, DLSS / FSR runtime, and Neural Rendering updater
- Existing FusionFix and user mods

## Social Club overlay status
The upstream v1.7.3 fix is confirmed to reject Direct3D devices created for windows other than GTA IV's game window. However, that code lives inside the RTX Remix Compatibility Mod. This corrected scaling package does **not** claim to solve the Steam/ReShade hotkey regression. Porting the small device-selection guard into the existing scaling bridge must be handled separately, without installing the full RTX Remix stack or replacing this project's D3D9 renderer.

Upstream references:
- [GTA IV RTX Remix Compatibility Mod](https://github.com/xoxor4d/gta4-rtx)
- [v1.7.3 release and installation requirements](https://github.com/xoxor4d/gta4-rtx/releases/tag/v1.7.3)
- [Social Club device-selection fix commit](https://github.com/xoxor4d/gta4-rtx/commit/19f1b7494783ce1cc67a3ca41a805154bd9b87c0)
