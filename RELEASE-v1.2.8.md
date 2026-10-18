# GTA IV Scaling v1.2.8 — Neural Rendering installer maintenance

**Installer-only maintenance of the v1.2.7 validated rendering release.** The b-bridge client, DXVK Vulkan presenter, feeder, ReShade input patch and DLSS/FSR rendering binaries are carried over with exact pinned checksums. No graphics code is rebuilt.

## Changes
- Explicit NR choice: **Automatic**, **Use my local DLL/ZIP/RAR**, or **Skip NR** (preserve an installed NR file).
- One NR installation stage. The outdated 310.8 stage no longer downloads a redundant archive.
- Automatic mode checks the installed DLL against the current GPU-specific approved SHA-256 first; if already current, no NR archive is downloaded.
- Local mode validates and installs the supplied DLL or archive, with no remote NR package download.
- Backup/rollback and SHA-256 checks retained, NVIDIA Authenticode check retained for RTX 50.
- Install/Repair from an already verified v1.2.7 updates the version receipt safely without overwriting rendering files, FusionFix or mods. Re-running v1.2.8 is similarly non-invasive. v1.2.6 is upgraded to the same approved bridge pin.
- Standalone **Update Neural Rendering only** uses the same updater and selection logic.

## Important
- The approved **v1.2.7 32-bit bridge client SHA-256** remains `B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF`.
- The bridge bypass mask remains `clientRedundantBypassMask=1032192`.
- The updater reads the approved NR catalog from the project's main branch. Thus a newly approved NR build may be offered by Automatic mode; existing approved hashes are checked before downloading.
- Supported NR on RTX 40 currently uses community-modified ShortFuse runtime; NR remains off by default until enabled in-game.
- Preserve `mods/CEExpandedInventory/inventory-v02.txt`; inventory mods are not bundled.
- Runtime behavior is validated by checksums, source/static tests and Windows installer compilation. Play-testing in GTA IV is still recommended after installing.
