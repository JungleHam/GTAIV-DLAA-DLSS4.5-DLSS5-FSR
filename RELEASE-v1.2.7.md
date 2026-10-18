# GTA IV Scaling v1.2.7 — validated loading-screen and shadow fix

**Status:** user-validated GTA IV Complete Edition bridge behavior for **DLAA, DLSS, and Neural Rendering** on an RTX 4070 Ti SUPER. Installer packaging is validated by Windows CI. FSR is included unchanged from v1.2.6, but the new bridge configuration has not yet been hardware-validated with FSR.

## Fixed
- **White loading-screen artwork** with the b-bridge renderer.
- **Shadows and lighting anomalies** caused by disabling the bridge's entire redundant-call optimization.
- The workaround keeps **StateBatch enabled** and the rest of the D3D9 setter optimizations intact.

## Pinned implementation
- Bundles the **exact 32-bit b-bridge client** confirmed working in the user's option **5 — SHADER OBJECTS + STREAM/GEOMETRY forwarded** test.
- Client SHA-256: `B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF`.
- Bridge settings: `eliminateRedundantSetterCalls = True`, `clientStateBatch = True`, `clientRedundantBypassMask = 1032192` (0xFC000).
- Precisely preserves the successful v1.2.6 build's DXVK presenter, bridge server, scaling add-on, FSR, DLSS, and ReShade input patch. The runtime contains no unrelated inventory/LuaModLoader mod.
- Baseline runtime was the passing v1.2.6 prep job [39115183838](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/actions/runs/39115183838). Pinned client came from passing job [39128635228](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/actions/runs/39128635228).

## Install and upgrade
1. **Close GTA IV and NvRemixBridge.exe.**
2. Download and run `GTAIV-Scaling-Setup-v1.2.7.exe` as administrator.
3. Select the folder containing `GTAIV.exe`, then **Install / Repair**.
4. On a v1.2.6 installation, the installer performs a **fast, reversible bridge-only upgrade** and retains other files, profiles, FusionFix, DXVK, and separately installed mods. A timestamped `_GTAIV_SCALING_PRE127_BACKUP_*` folder stores the old client, configuration and receipt.
5. Older and fresh installations use the normal full installer path with v1.2.7's pinned client.
6. Launch GTA IV and confirm loading artwork and shadows; the in-game Add-ons controls remain familiar.

**Compatibility:** Because this is a bridge fix, the NR DLL, DLSS and FSR settings are intentionally unchanged. Avoid running old A/B diagnostic scripts on top of v1.2.7. Inventory mods and LuaModLoader are separate.

## Verification
The release workflow verifies the source archive's SHA-256, the exact user-tested DLL SHA-256, each runtime file hash and the package file delta, recompiles the Inno Setup EXE on Windows and publishes checksums. CI cannot perform GTA IV hardware rendering tests; these were reported by the user for the exact pinned DLL and setting combination.
