# Latest FusionFix only

Use `GTAIV-FusionFix-Latest-Launcher-v1.0.0.exe` when you want the **newest official stable FusionFix** on a clean GTA IV: Complete Edition installation, without installing the project's graphics reconstruction stack.

1. Close GTA IV.
2. Run the small launcher. Select the folder that contains `GTAIV.exe`.
3. The launcher queries the official `ThirteenAG/GTAIV.EFLC.FusionFix` GitHub `releases/latest` endpoint.
4. It downloads **exactly** `GTAIV.EFLC.FusionFix.zip` from that release and verifies the official release asset's `sha256:` digest.
5. It stages the verified package, checks the paths and the expected `dinput8.dll`, backs up every existing file that would be overwritten, then installs FusionFix.
6. Existing `GTAIV.EFLC.FusionFix.cfg` / `.ini` are not overwritten.
7. The installed release and SHA-256 are written to `GTAIV-FUSIONFIX-LATEST.json`; repeated runs on the same release do nothing unless `-Force` is supplied to the underlying script.

Backups are stored under `_GTAIV_FUSIONFIX_BACKUP_<timestamp>_<suffix>` beside the game executable. If installation file copying fails, it attempts to restore the previous files.

**It does not install DLSS, FSR, DXVK, ReShade, b-bridge, or inventory/weapon mods.** The GTA IV Scaling install/repair action continues using its validated pinned FusionFix release until the entire reconstruction stack has been compatibility-tested with the newer FusionFix.

For integration in the standard GTA IV Scaling installer, choose **Install / Update latest stable FusionFix ONLY** from the action list. This option reuses the identical script and needs no NVIDIA GPU or ReShade prerequisite.

The actual latest stable release is deliberately resolved at execution time. The minimum security requirement is an official release zip with a GitHub-published SHA-256 digest. The updater does not install prereleases or arbitrary assets. On network or integrity failure, it stops without changing game files.

Note: FusionFix v5.1.x changed some settings. The upstream developers warn that preferences may shift; revisit FusionFix settings after an upgrade if anything looks different.

## Tests
Windows CI validates correct mocked release selection, SHA-256 verification, preserved existing settings, backup, idempotence, clean-install operation without Scaling, and compiles the portable Inno Setup GUI. End-user testing with the full upstream package is still recommended before general release.
