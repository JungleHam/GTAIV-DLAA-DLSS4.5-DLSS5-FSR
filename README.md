# GTA IV Scaling

GTA IV Scaling is a unified reconstruction and anti-aliasing layer for **GTA IV: Complete Edition** on Windows.

It adds live switching between **native rendering**, **NVIDIA DLAA / DLSS**, and **AMD FidelityFX FSR** from one runtime and one installer.

## Installation

### What you need

- **GTA IV: Complete Edition**
- **Windows 10/11 64-bit**
- Administrator access for the ReShade/Vulkan setup
- The official **ReShade 6.8.0 Full Add-On Support** installer when setting up from a clean game

Everything else required by the project is handled by the installer.

### Clean installation

0. Install the latest, clean GTA IV (Steam version tested, Rockstar Game Launcher version wasn't but probably fine) 
1. Download **`GTAIV-Scaling-Setup-v1.2.3.exe`** from the [Releases](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/releases) page.
2. Run it as **Administrator**.
3. Select the folder containing **`GTAIV.exe`**.
4. Choose **Install / Repair GTA IV Scaling 1.2.3**.
5. If FusionFix is missing, the installer downloads and installs pinned **FusionFix 5.0.1**.
6. Launch GTA IV once to the main menu, close the game, and run the installer again so FusionFix can create its first-run state.
7. If the scaling foundation is not already installed, select the official **ReShade 6.8.0 Full Add-On Support** setup EXE when asked.
8. Finish installation and launch GTA IV.

There is **no DLSS-vs-FSR installer choice**. The full shared runtime is installed once and the game only shows the scaling technologies supported by the detected GPU.

### Repair / upgrade

Run the v1.2.3 installer and choose **Install / Repair**. If an intact v1.2.2 installation is detected, setup performs a **configuration-only upgrade**: it backs up the DXVK configuration and receipt, removes the obsolete forced 16:9 filter, and preserves the working DLAA/DLSS/FSR binaries and per-backend settings. Other installs use the normal install/repair path.

The installer backs up the project-owned scaling files before replacing the stack.

### Removal

Run the same installer and choose one of two uninstall modes:

- **Remove GTA IV Scaling, keep FusionFix** — removes the scaling runtime, .trex, project ReShade files, receipts, logs and project backup folders, then restores the pre-scaling FusionFix state.
- **Completely remove GTA IV Scaling and FusionFix** — performs the same project cleanup, then removes the pinned FusionFix package files too. It does not intentionally delete unrelated GTA IV mods.

The shared official ReShade installation is restored away from the project input patch rather than blindly deleted, because it may be used by other games.

### Open the in-game controls

```text
Home key -> Add-ons -> GTA IV Scaling 1.2.2
```

## Features

- **DLAA** — native-resolution NVIDIA temporal anti-aliasing.
- **DLSS Super Resolution** — Ultra Quality 77%, Quality 67%, Balanced 58%, Performance 50%, Ultra Performance 33%.
- **DLSS Custom Quality** — adjustable 10–100% render scale with an Apply button.
- **DLSS 5 Neural Rendering** — optional toggle on RTX 20/30/40/50, up to 5 passes, styles and granular tuning controls.
- **NVIDIA sharpening** — independent 0.00–1.50 sharpening control.
- **NVIDIA temporal AA controls** — Auto / 8 / 16 / 32 jitter phases plus X/Y compensation; calibrated default is 8 phases + -X/-Y.
- **FSR Native AA** — 100% FidelityFX FSR 3.1.4 Vulkan.
- **FSR scaling** — Ultra Quality 77%, Quality 66.7%, Balanced 59%, Performance 50%, Ultra Performance 33%, plus custom 10–100% scale.
- **AMD RCAS** — independent 0.00–1.00 sharpening control.
- **Live backend switching** — Off / NVIDIA / AMD without restarting; vendor switches use a safe native midpoint.
- **GPU-aware UI** — RTX shows NVIDIA + FSR; non-RTX hides NVIDIA and keeps FSR.
- **Independent backend settings** — NVIDIA and AMD keep their own scale, sharpening and temporal state.
- **Unified installer** — Install / Repair / Remove from one EXE, with FusionFix/dependency handling and automatic RTX 20/30/40/50 NR setup.
- **Diagnostics** — backend state, resolution, jitter, FSR and NR information available in the Advanced panel.

**Upcoming**
- DLSS 5 NR Support for FSR scaling (reearching the possibility rn)
- DLSS and FSR Frame Gen
- FSR 1.0 support for older GPUs

## Current release

**v1.2.3** (installer/configuration hotfix; reconstruction runtime remains v1.2.2)

Installer: **GTAIV-Scaling-Setup-v1.2.3.exe**

> **v1.2.3 hotfix:** removes the inherited DXVK forced-16:9 filter, which hid non-16:9 display modes from GTA IV. It preserves modeCountCompatibility for GTA IV's fixed-size mode list. Existing v1.2.2 users can install on top without replacing the calibrated scaling binaries. The in-game Add-ons title remains 1.2.2 because its binary is unchanged.

## Screenshots

[Screenshots](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/tree/main/screenshots)

## GPU support

| GPU | Off / Native | AMD FidelityFX FSR | NVIDIA DLAA / DLSS | DLSS Neural Rendering |
| --- | --- | --- | --- | --- |
| RTX 20 Series | Yes | Yes | Yes | Yes, SF-v2, set to OFF by default |
| RTX 30 Series | Yes | Yes | Yes | Yes, SF-v2, set to OFF by default |
| RTX 40 Series | Yes | Yes | Yes | Yes, set to OFF by default |
| RTX 50 Series | Yes | Yes | Yes | Yes, set to OFF by default |
| GTX / AMD / Intel / other non-RTX | Yes | Yes | Hidden | No |

The installer detects NVIDIA RTX capability and writes it into the runtime configuration.

On non-RTX systems the NVIDIA choice is hidden, and an old saved NVIDIA selection is automatically moved to AMD FSR instead of trying to open an unavailable backend.

v1.2.1 enables Neural Rendering on RTX 20/30 using the ShortFuse 310.8.SF-v2 compatibility runtime. RTX 40 keeps the existing project-tested 310.8.0 compatibility runtime, while RTX 50 keeps the NVIDIA-signed 310.8.0 runtime. NR remains OFF by default on every supported RTX generation.

## In-game controls

Open:

```text
Home key -> Add-ons -> GTA IV Scaling 1.2.2
```

The main panel is **GTA IV Scaling**.

### Scaling Technology

On RTX:

```text
Off - Native
NVIDIA DLAA / DLSS
AMD FidelityFX FSR
```

On non-RTX:

```text
Off - Native
AMD FidelityFX FSR
```

Backend switches are live.

NVIDIA <-> AMD switches are serialized through a native/raw midpoint so one vendor backend is not destroyed while another still owns GPU resources. There is no silent cross-vendor fallback.

**Off - Native** is a true reconstruction-off path: no DLAA, DLSS, FSR, or Neural Rendering evaluation after the native transition completes.

NVIDIA and AMD settings are stored independently so changing one backend does not overwrite the other backend's scale or sharpening choices.

## NVIDIA DLAA / DLSS

The NVIDIA path uses the project's pinned DLSS runtime and supports both DLAA and Super Resolution.

### Presets

- **DLAA Native — 100%**
- **Custom Ultra Quality — 77%**
- **Quality — 67%**
- **Balanced — 58%**
- **Performance — 50%**
- **Ultra Performance — 33%**
- **Custom Render Scale — 10% to 100%**

The custom scale slider is staged: moving it only changes the preview value. **Apply** performs the resolution change, avoiding constant resize churn while dragging the slider.

100% custom scale resolves to DLAA/native reconstruction.

If NVIDIA rejects feature creation at an unusual forced scale, the runtime reports it and keeps the previous valid reconstruction instead of silently switching vendor backends.

### NVIDIA sharpening

Independent post-DLSS sharpening:

- range: **0.00 to 1.50**
- 0.00 = off
- 0.35 = mild
- 0.75 = strong
- 1.50 = extreme

This is separate from AMD RCAS.

### Temporal AA / jitter controls

Advanced controls include:

- **Auto**
- **8 phases**
- **16 phases**
- **32 phases**

NVIDIA also exposes live jitter-compensation sign calibration:

- +X / +Y
- -X / -Y
- +X / -Y
- -X / +Y

The hardware-tested v1.2.0 default is:

```text
Jitter sequence: 8 phases
NVIDIA jitter compensation: -X / -Y
```

That calibration preserved the strong AA benefit while removing the excessive shimmer seen with the earlier sign convention. DLAA was clean in hardware testing; aggressive lower render scales can still show the mild temporal wobble expected from lower-resolution temporal reconstruction.

## AMD FidelityFX FSR

v1.2.0 adds an independent **FidelityFX FSR 3.1.4 Vulkan** reconstruction backend.

It does not use NGX as a hidden fallback.

### FSR presets

- **Native AA — 100%**
- **Ultra Quality — 77%**
- **Quality — 66.7%**
- **Balanced — 59%**
- **Performance — 50%**
- **Ultra Performance — 33%**
- **Custom Render Scale — 10% to 100%**

FSR has its own custom scale and render planner, independent of the NVIDIA profile/scale state.

### AMD RCAS sharpening

Independent FidelityFX RCAS control:

- range: **0.00 to 1.00**
- 0.00 = off
- 0.25 = mild
- 0.50 = medium
- 1.00 = maximum

### FSR temporal behavior

The AMD path uses GTA IV's exact raster jitter handoff with FidelityFX's own independent phase planning.

v1.2.0 also switches FSR to fixed/default exposure instead of the earlier internal auto-exposure path. This removed the brightness/vignette-like pulsing seen during hardware testing.

The calibrated GTA IV camera/depth contract used by FSR is:

- near plane: 0.05
- far plane: 1500
- vertical FOV: 45 degrees
- finite, non-reversed depth

## DLSS Neural Rendering

Neural Rendering is optional and starts **OFF**.

The installer only installs the NR runtime on the tested generations:

- **RTX 40 Series:** tested compatibility runtime
- **RTX 50 Series:** NVIDIA-signed runtime

RTX 20/30 use DLAA/DLSS without NR.

If you already have the exact supported `nvngx_dlssnr.dll`, the installer can use a local copy instead; it is still hash-checked.

### NR controls

Advanced NR controls include:

- style:
  - Default
  - Natural
  - Cinematic
- Intensity: **0.00–2.00**
- Local Tone: **0.00–2.00**
- Local Structure: **0.00–2.00**
- Skin Structure: **0.00–2.00**
- Auto Mask
- UI Correction
- **1–5 Neural Rendering passes**
- Reset NR Advanced

The reset defaults are:

```text
Style: Default
Intensity: 1.00
Local Tone: 1.00
Local Structure: 1.00
Skin Structure: 1.00
Auto Mask: ON
UI Correction: OFF
```

## Diagnostics and state

The Advanced/Diagnostics UI exposes useful runtime state including requested/active backend, backend transition state, requested/source/output resolution, saved custom scale, temporal jitter state, NVIDIA compensation, FSR state and NR tuning.

The runtime preserves per-backend configuration across live switches and normal restarts.

## Installer behavior

The v1.2.0 installer is a single unified **Install / Repair** flow.

It automatically handles or verifies the project-owned dependencies, including:

- FusionFix 5.0.1
- the pinned GTA IV bridge/presenter runtime
- LumeniteFX
- the project ReShade input patch
- the project NVIDIA DLAA/DLSS runtime
- the AMD FidelityFX FSR 3.1.4 backend
- GPU-matched NR on RTX 40/50

The normal manual prerequisite is the official **ReShade 6.8.0 Full Add-On Support** installer on a fresh setup.

The installer also records the detected GPU and installed feature capability in `GTAIV_SCALING_INSTALLED.txt`.

## Why the bridge exists

GTA IV is a **32-bit Direct3D 9** game, while the modern reconstruction stack is 64-bit.

The project bridges the game into a 64-bit Vulkan/ReShade environment:

```text
GTAIV.exe (32-bit D3D9)
        |
        v
FusionFix
        |
        v
b-bridge client
        |
        v
NvRemixBridge.exe (64-bit)
        |
        v
custom DXVK / Vulkan presenter
        |
        v
ReShade + LumeniteFX
        |
        +--> Off / Native
        |
        +--> NVIDIA DLAA / DLSS
        |       |
        |       +--> optional DLSS Neural Rendering
        |
        +--> AMD FidelityFX FSR 3.1.4
        |
        v
display
```

The bridge also carries GTA IV's temporal raster jitter and the input data required by reconstruction.

## ReShade input patch

GTA IV owns the game window while ReShade runs in the separate 64-bit bridge process.

The project includes a ReShade 6.8.0 input patch that relays keyboard and mouse input across that process boundary so the ReShade overlay remains usable.

## v1.2.0 release hashes

```text
Installer:
882FB425D9ABE8CFEA25583049B00A252AE730E4480EB3C78867691FEA446F85

Runtime ZIP:
7AE9FC16FF6AF6A49EF605B18B2606A8986F1E962E3A519C4DB6A5053834969B

v1.2 feeder:
AF35011DC5914DF2DB6B1C49B2EDDE751831F4F8AF53B80A26D7C079CA26BDFF

ReShade b-bridge input patch:
D5BD8CB2B6E935506888EA71711361B9AFCD72ED7C70926C0F52E8F8E47C7510
```

More pinned component details are in [`manifests/versions.json`](manifests/versions.json).

## Useful docs

- [Prerequisites and pinned packages](docs/PREREQUISITES.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Third-party components / redistribution policy](docs/THIRD-PARTY.md)
- [ReShade input patch](docs/RESHade-INPUT-PATCH.md)
- [FSR architecture and hardware checkpoints](docs/FSR_ARCHITECTURE.md)

## Credits

- [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix)
- [b-bridge](https://github.com/gutbash/b-bridge)
- [DXVK](https://github.com/doitsujin/dxvk)
- [ReShade](https://github.com/crosire/reshade)
- [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder)
- [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)
- [NVIDIA DLSS](https://github.com/NVIDIA/DLSS)
- [AMD FidelityFX SDK](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK)
- [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo)

This is an independent community integration project and is not affiliated with Rockstar Games, NVIDIA, AMD, or the upstream projects above.
