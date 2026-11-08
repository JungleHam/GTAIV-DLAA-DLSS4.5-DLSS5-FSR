@echo off
setlocal
set "GTAIV_UNINSTALL_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:GTAIV_UNINSTALL_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Self = $env:GTAIV_UNINSTALL_SELF
$Temp = Join-Path $env:TEMP ("GTAIV_DLAA_UNINSTALL_" + $PID)
$Safety = Join-Path $Temp 'safety'
$Log = Join-Path $Temp 'Uninstall-DLAA.log'
$TranscriptStarted = $false
$Succeeded = $false
$GlobalReShade = 'C:\ProgramData\ReShade\ReShade64.dll'
$GlobalReShadeBackup = 'C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input'

function Fail([string]$Message) { throw $Message }
function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Resolve-GameFolder {
    Write-Host ''
    Write-Host 'Enter the GTA IV folder that contains GTAIV.exe.' -ForegroundColor Cyan
    $raw = (Read-Host 'GTA IV folder').Trim().Trim('"')
    if (-not $raw) { Fail 'No folder entered.' }
    if ((Test-Path -LiteralPath $raw -PathType Leaf) -and ([IO.Path]::GetFileName($raw) -ieq 'GTAIV.exe')) { $raw = Split-Path -Parent $raw }
    if (Test-Path -LiteralPath (Join-Path $raw 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $raw).Path }
    $nested = Join-Path $raw 'GTAIV'
    if (Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $nested).Path }
    Fail 'GTAIV.exe was not found in that folder.'
}
function Has-PatchMarker([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
        return $ascii.Contains('b-bridge input relay')
    } catch { return $false }
}
function Copy-Path([string]$Source,[string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-Path -LiteralPath $Source -PathType Container) { Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force }
    else { Copy-Item -LiteralPath $Source -Destination $Destination -Force }
}
function Test-DlaaPreinstallBackup([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $plugins = Join-Path $Path 'plugins'
    if (-not (Test-Path -LiteralPath $plugins -PathType Container)) { return $false }
    return $null -ne (Get-ChildItem -LiteralPath $plugins -File -Filter '*FusionFix*.cfg' -ErrorAction SilentlyContinue | Select-Object -First 1)
}
function Find-DlaaPreinstallBackup([string]$Game) {
    $manifest = Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt'
    if (Test-Path -LiteralPath $manifest) {
        $text = [IO.File]::ReadAllText($manifest)
        $m = [regex]::Match($text,'(?ms)Pre-install backup:\s*\r?\n(?<path>[^\r\n]+)')
        if ($m.Success) {
            $candidate = $m.Groups['path'].Value.Trim()
            if (Test-DlaaPreinstallBackup $candidate) { return $candidate }
        }
    }
    $candidates = @(Get-ChildItem -LiteralPath $Game -Directory -Filter '_DLAA_PREINSTALL_BACKUP_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($candidate in $candidates) {
        if (Test-DlaaPreinstallBackup $candidate.FullName) { return $candidate.FullName }
    }
    return $null
}
function Snapshot-Current([string]$Game) {
    New-Item -ItemType Directory -Path $Safety -Force | Out-Null
    foreach ($name in @('a_gta4-rtx.asi','d3d9.dll','d3d9Hooked.dll','dxvk.conf','commandline.txt','DLAA_INSTALL_MANIFEST.txt','DLAA_AIO_install.log','DLSS_FULL_INSTALLED.txt','DLSS_FULL_install.log','DLSS_FULL_uninstall.log','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat')) {
        Copy-Path (Join-Path $Game $name) (Join-Path $Safety $name)
    }
    Copy-Path (Join-Path $Game '.trex') (Join-Path $Safety '.trex')
    $plugins = Join-Path $Game 'plugins'
    if (Test-Path -LiteralPath $plugins) {
        $cfg = Get-ChildItem -LiteralPath $plugins -File -Filter '*FusionFix*.cfg' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cfg) { Copy-Path $cfg.FullName (Join-Path $Safety ('plugins\' + $cfg.Name)) }
        $ini = Join-Path $plugins 'GTAIV.EFLC.FusionFix.ini'
        Copy-Path $ini (Join-Path $Safety 'plugins\GTAIV.EFLC.FusionFix.ini')
    }
    Copy-Path $GlobalReShade (Join-Path $Safety 'global-reshade\ReShade64.dll')
    Copy-Path $GlobalReShadeBackup (Join-Path $Safety 'global-reshade\ReShade64.dll.pre-bbridge-input')
}
function Restore-Safety([string]$Game) {
    $trex = Join-Path $Game '.trex'
    if (Test-Path -LiteralPath $trex) { Remove-Item -LiteralPath $trex -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($name in @('a_gta4-rtx.asi','d3d9.dll','d3d9Hooked.dll','dxvk.conf','commandline.txt','DLAA_INSTALL_MANIFEST.txt','DLAA_AIO_install.log','DLSS_FULL_INSTALLED.txt','DLSS_FULL_install.log','DLSS_FULL_uninstall.log','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat')) {
        $dst = Join-Path $Game $name
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
        Copy-Path (Join-Path $Safety $name) $dst
    }
    Copy-Path (Join-Path $Safety '.trex') $trex
    $plugins = Join-Path $Game 'plugins'
    $cfg = Get-ChildItem -LiteralPath (Join-Path $Safety 'plugins') -File -Filter '*FusionFix*.cfg' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cfg) { Copy-Path $cfg.FullName (Join-Path $plugins $cfg.Name) }
    Copy-Path (Join-Path $Safety 'plugins\GTAIV.EFLC.FusionFix.ini') (Join-Path $plugins 'GTAIV.EFLC.FusionFix.ini')

    Copy-Path (Join-Path $Safety 'global-reshade\ReShade64.dll') $GlobalReShade
    Copy-Path (Join-Path $Safety 'global-reshade\ReShade64.dll.pre-bbridge-input') $GlobalReShadeBackup
}
function Restore-PreinstallState([string]$Game,[string]$Backup) {
    $trex = Join-Path $Game '.trex'
    if (Test-Path -LiteralPath $trex) { Remove-Item -LiteralPath $trex -Recurse -Force }

    foreach ($name in @('d3d9.dll','d3d9Hooked.dll','dxvk.conf','commandline.txt')) {
        $p = Join-Path $Game $name
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    foreach ($name in @('d3d9.dll','dxvk.conf','commandline.txt')) {
        Copy-Path (Join-Path $Backup $name) (Join-Path $Game $name)
    }

    $backupCfg = Get-ChildItem -LiteralPath (Join-Path $Backup 'plugins') -File -Filter '*FusionFix*.cfg' -ErrorAction Stop | Select-Object -First 1
    if (-not $backupCfg) { Fail 'The pre-DLAA backup is missing the FusionFix CFG.' }
    Copy-Path $backupCfg.FullName (Join-Path $Game ('plugins\' + $backupCfg.Name))
    Copy-Path (Join-Path $Backup 'plugins\GTAIV.EFLC.FusionFix.ini') (Join-Path $Game 'plugins\GTAIV.EFLC.FusionFix.ini')

    foreach ($name in @('DLAA_INSTALL_MANIFEST.txt','DLAA_AIO_install.log','DLSS_FULL_INSTALLED.txt','DLSS_FULL_install.log','DLSS_FULL_uninstall.log','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','_GTAIV_DLSS_Install-DLAA-Core.bat','_GTAIV_DLSS_Install-DLSS-Full-Core.bat')) {
        $p = Join-Path $Game $name
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}
function Validate-RestoredState([string]$Game,[string]$Backup) {
    if (Test-Path -LiteralPath (Join-Path $Game '.trex')) { Fail '.trex still exists after cleanup.' }
    if (Test-Path -LiteralPath (Join-Path $Game 'd3d9Hooked.dll')) { Fail 'd3d9Hooked.dll still exists after cleanup.' }
    foreach ($name in @('d3d9.dll','dxvk.conf','commandline.txt')) {
        $src = Join-Path $Backup $name
        $dst = Join-Path $Game $name
        if (Test-Path -LiteralPath $src) {
            if (-not (Test-Path -LiteralPath $dst)) { Fail "Restore validation failed: missing $name" }
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash) { Fail "Restore validation failed: $name differs from pre-DLAA backup." }
        } elseif (Test-Path -LiteralPath $dst) {
            Fail "Restore validation failed: $name did not exist before DLAA but still exists now."
        }
    }
    $backupCfg = Get-ChildItem -LiteralPath (Join-Path $Backup 'plugins') -File -Filter '*FusionFix*.cfg' | Select-Object -First 1
    $liveCfg = Join-Path $Game ('plugins\' + $backupCfg.Name)
    if (-not (Test-Path -LiteralPath $liveCfg)) { Fail 'FusionFix CFG is missing after restore.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backupCfg.FullName).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $liveCfg).Hash) { Fail 'FusionFix CFG does not match the pre-DLAA state.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) { Fail 'FusionFix dinput8.dll is missing after restore.' }
    foreach ($name in @('DLAA_INSTALL_MANIFEST.txt','DLSS_FULL_INSTALLED.txt','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat')) {
        if (Test-Path -LiteralPath (Join-Path $Game $name)) { Fail "Project file still exists after cleanup: $name" }
    }
    if (Has-PatchMarker $GlobalReShade) { Fail 'The patched ReShade global DLL is still active.' }
    if (Test-Path -LiteralPath $GlobalReShadeBackup) { Fail 'The ReShade input-patch backup file still exists.' }
}
function Remove-ProjectBackups([string]$Game) {
    foreach ($pattern in @('_DLAA_PREINSTALL_BACKUP_*','_DLSS_FULL_PREINSTALL_BACKUP_*','_DLSS_FULL_UNINSTALL_SAFETY_*','_DLAA_UNINSTALL_SAFETY_*','_GTAIV_SCALING_PRE*_BACKUP_*')) {
        Get-ChildItem -LiteralPath $Game -Directory -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    }
    $canonical = Join-Path $Game '_DLSS_FULL_DLAA_BASELINE'
    if (Test-Path -LiteralPath $canonical) { Remove-Item -LiteralPath $canonical -Recurse -Force }
}

if (-not (Is-Admin)) {
    Write-Host 'Administrator permission is required. Approve the Windows prompt.' -ForegroundColor Yellow
    $p = Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

try {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' GTA IV - REMOVE THIS PROJECT -> RESTORE FUSIONFIX BASELINE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green

    $Game = Resolve-GameFolder
    $Trex = Join-Path $Game '.trex'
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) { Fail 'FusionFix is not detected. Refusing to modify this folder.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }

    $Backup = Find-DlaaPreinstallBackup $Game
    if (-not $Backup) { Fail 'No trustworthy _DLAA_PREINSTALL_BACKUP_ was found. Nothing was changed.' }

    Write-Host ''
    Write-Host "Game: $Game"
    Write-Host "Restore point: $Backup" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'This removes:' -ForegroundColor Yellow
    Write-Host '  DLAA / DLSS / Neural Rendering / b-bridge / .trex'
    Write-Host '  ReShade Vulkan layer + this project input patch'
    Write-Host '  project runtime helpers, receipts, logs and rollback folders'
    Write-Host 'FusionFix itself stays installed and its pre-DLAA config is restored.' -ForegroundColor Green
    $ok = Read-Host 'Continue? [y/N]'
    if ($ok -notmatch '^(y|yes)$') { exit 0 }

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    Start-Transcript -LiteralPath $Log -Force | Out-Null
    $TranscriptStarted = $true
    Snapshot-Current $Game

    $needReShadeCleanup = (Test-Path -LiteralPath $GlobalReShadeBackup) -or (Has-PatchMarker $GlobalReShade)
    if ($needReShadeCleanup) {
        Write-Host ''
        Write-Host '[1/3] Removing this project''s ReShade input patch...' -ForegroundColor Cyan
        if (Test-Path -LiteralPath $GlobalReShadeBackup) {
            Copy-Item -LiteralPath $GlobalReShadeBackup -Destination $GlobalReShade -Force
            Remove-Item -LiteralPath $GlobalReShadeBackup -Force
        } elseif (Has-PatchMarker $GlobalReShade) {
            Fail 'The project ReShade input patch is active, but its official ReShade backup is missing. Reinstall official ReShade using the ReShade GitHub project page and its official-site link, then run removal again.'
        }
    } else {
        Write-Host '[1/3] No project ReShade input-patch state detected.' -ForegroundColor DarkGray
    }

    Write-Host '[2/3] Restoring the exact pre-DLAA FusionFix files...' -ForegroundColor Cyan
    Restore-PreinstallState $Game $Backup
    Validate-RestoredState $Game $Backup

    Write-Host '[3/3] Removing project rollback folders...' -ForegroundColor Cyan
    Remove-ProjectBackups $Game

    $Succeeded = $true
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' DONE - GTA IV + FUSIONFIX BASELINE RESTORED' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host 'Everything installed by this project has been removed from the GTA IV runtime.' -ForegroundColor Green
    Write-Host 'FusionFix, GTA IV, and the official ReShade installation were left in place.' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally to verify the clean FusionFix baseline.' -ForegroundColor White
}
catch {
    Write-Host ''
    Write-Host ('UNINSTALL FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    if (Test-Path -LiteralPath $Safety) {
        Write-Host 'Attempting to restore the state from before this uninstall...' -ForegroundColor Yellow
        try {
            Restore-Safety $Game
            Write-Host 'Pre-uninstall runtime restored where possible.' -ForegroundColor Green
        } catch {
            Write-Host ('Rollback error: ' + $_.Exception.Message) -ForegroundColor Red
        }
    }
    Write-Host "Diagnostic folder kept at: $Temp" -ForegroundColor Yellow
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {}; $TranscriptStarted = $false }
    Read-Host 'Press Enter to close'
    exit 1
}
finally {
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {}; $TranscriptStarted = $false }
    if ($Succeeded -and (Test-Path -LiteralPath $Temp)) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}

exit 0
