@echo off
setlocal
set "GTAIV_SETUP_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:GTAIV_SETUP_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Self = $env:GTAIV_SETUP_SELF
$Repo = 'JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR'
$RuntimeTag = 'v1.2.10'
$ReleaseApi = 'https://api.github.com/repos/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/releases/tags/v1.2.10'
$PatchedReShadeAsset = 'ReShade64-bbridge.dll'
$PatchedReShadeHash = '0BD8636C03AB3B9D2AD8FF400A834F2FE40AC369AB3314E8E17E0989924AFF48'
$GlobalReShade = 'C:\ProgramData\ReShade\ReShade64.dll'
$GlobalReShadeBackup = 'C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input'
$Temp = Join-Path $env:TEMP ("GTAIV_DLAA_RELEASE_" + $PID)
$CoreTemp = $null
$ReShadeSetup = $env:GTAIV_SETUP_RESHADE
$LumenitePackage = $env:GTAIV_SETUP_LUMENITE
$ReShadeSetupHash = 'AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445'
$LumenitePackageHash = '572FEFB20D466AFE50998E16996B4833BEC675264485C99FE768A2337636E756'

function Is-Admin { $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $p=New-Object Security.Principal.WindowsPrincipal($id); return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Fail([string]$m) { throw $m }
function Write-SetupResultIfEmpty([string]$Message) {
    if (-not $env:GTAIV_SETUP_RESULT_FILE) { return }
    try {
        if ((-not (Test-Path -LiteralPath $env:GTAIV_SETUP_RESULT_FILE -PathType Leaf)) -or
            ((Get-Item -LiteralPath $env:GTAIV_SETUP_RESULT_FILE).Length -eq 0)) {
            [IO.File]::WriteAllText($env:GTAIV_SETUP_RESULT_FILE,$Message,[Text.UTF8Encoding]::new($false))
        }
    } catch {}
}
function Resolve-ProjectAssetUrl([string]$AssetName) {
    $headers=@{'User-Agent'='GTAIV-DLSS-Setup'}
    $release=Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $ReleaseApi
    $asset=@($release.assets | Where-Object { $_.name -eq $AssetName }) | Select-Object -First 1
    if (-not $asset -or -not $asset.browser_download_url) { Fail "Project release asset was not found: $AssetName" }
    return [string]$asset.browser_download_url
}
function Download([string]$u,[string]$p) {
    Write-Host "Downloading project release asset: $u" -ForegroundColor DarkGray
    $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) { & curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $p $u; if ($LASTEXITCODE -ne 0) { Fail "Download failed: $u" } }
    else { Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p }
    if (-not (Test-Path -LiteralPath $p)) { Fail "Downloaded file is missing: $p" }
}
function Assert-SHA256([string]$p,[string]$expected) {
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant()
    if ($actual -ne $expected.ToUpperInvariant()) { Fail "SHA256 mismatch for $p`nExpected: $expected`nActual:   $actual" }
}
function Resolve-GameFolder {
    if ($env:GTAIV_SETUP_GAME) { return (Resolve-Path -LiteralPath $env:GTAIV_SETUP_GAME).Path }
    Write-Host ''; Write-Host 'Enter the GTA IV folder that contains GTAIV.exe.' -ForegroundColor Cyan
    $raw=(Read-Host 'GTA IV folder').Trim().Trim('"'); if (-not $raw) { Fail 'No folder entered.' }
    if ((Test-Path -LiteralPath $raw -PathType Leaf) -and ([IO.Path]::GetFileName($raw) -ieq 'GTAIV.exe')) { $raw=Split-Path -Parent $raw }
    if (Test-Path -LiteralPath (Join-Path $raw 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $raw).Path }
    $nested=Join-Path $raw 'GTAIV'; if (Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $nested).Path }
    Fail 'GTAIV.exe was not found in that folder.'
}
function Has-PatchMarker([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try { $ascii=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($path)); return $ascii.Contains('b-bridge input relay') } catch { return $false }
}
function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value) {
    $text=if(Test-Path -LiteralPath $Path){[IO.File]::ReadAllText($Path)}else{''}; $pat='(?m)^\s*'+[regex]::Escape($Key)+'\s*=\s*.*$'; $line="$Key = $Value"
    if($text -match $pat){$text=[regex]::Replace($text,$pat,$line)}else{if($text.Length -gt 0 -and -not $text.EndsWith("`n")){$text+="`r`n"};$text+=$line+"`r`n"}
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}
function Validate-UserPrereqs {
    if (-not $ReShadeSetup -or -not (Test-Path -LiteralPath $ReShadeSetup -PathType Leaf)) { Fail 'Select the official ReShade 6.8.0 Full Add-On Support installer described by the setup prerequisite guide.' }
    Assert-SHA256 $ReShadeSetup $ReShadeSetupHash
    if (-not $LumenitePackage -or -not (Test-Path -LiteralPath $LumenitePackage -PathType Leaf)) { Fail 'Select the official LumeniteFX ZIP for commit f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9.' }
    Assert-SHA256 $LumenitePackage $LumenitePackageHash
}
function Ensure-ReShade([string]$Game,[string]$Trex) {
    if ((Test-Path -LiteralPath $GlobalReShade) -and (Test-Path -LiteralPath (Join-Path $Trex 'ReShade.ini'))) { return }
    Write-Host '[2/2] Installing official ReShade 6.8.0 Add-On Support...' -ForegroundColor Cyan
    $target=Join-Path $Trex 'NvRemixBridge.exe'; if (-not (Test-Path -LiteralPath $target)) { Fail 'NvRemixBridge.exe is missing; reinstall the DLAA baseline first.' }
    $p=Start-Process -FilePath $ReShadeSetup -ArgumentList @("`"$target`"",'--api','vulkan','--headless') -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "Official ReShade setup failed with exit code $($p.ExitCode)." }
    if (-not (Test-Path -LiteralPath $GlobalReShade)) { Fail 'Official ReShade Vulkan DLL was not installed.' }
}

if (-not (Is-Admin)) { Write-Host 'Administrator permission is required. Approve the Windows prompt.' -ForegroundColor Yellow; $p=Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru; exit $p.ExitCode }

try {
    Write-Host ''; Write-Host '============================================================' -ForegroundColor Green; Write-Host ' GTA IV - DLAA + ReShade input patch' -ForegroundColor Green; Write-Host '============================================================' -ForegroundColor Green
    $Game=Resolve-GameFolder; $Trex=Join-Path $Game '.trex'
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) { Fail 'FusionFix is not detected. Normal users should use GTAIV-DLSS-Setup.exe, which downloads and installs FusionFix automatically. This fallback BAT expects FusionFix to be present already.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }; if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }
    if (Test-Path -LiteralPath (Join-Path $Trex 'm3k-nr.ini')) { Fail 'DLSS Full is already installed. Do not run the DLAA baseline installer over it.' }
    Validate-UserPrereqs

    $dlaaReady=(Test-Path -LiteralPath (Join-Path $Trex 'NvRemixBridge.exe')) -and (Test-Path -LiteralPath (Join-Path $Trex 'dlss5-feed.addon64')) -and (Test-Path -LiteralPath (Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt'))
    $reshadePatchedBefore=Has-PatchMarker $GlobalReShade
    Write-Host ''; Write-Host "Game: $Game"; Write-Host ("DLAA baseline: "+$(if($dlaaReady){'already installed - will keep it'}else{'will install'})); Write-Host ("ReShade input patch: "+$(if($reshadePatchedBefore){'already installed'}else{'will install from this project release'}))
    Write-Host 'Official ReShade was selected by the user; LumeniteFX and other GitHub-hosted dependencies are handled by setup.' -ForegroundColor Green
    $ok=if($env:GTAIV_SETUP_GAME){'y'}else{Read-Host 'Continue? [Y/n]'}; if($ok -and $ok -notmatch '^(y|yes)$'){exit 0}
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null

    if (-not $dlaaReady) {
        Write-Host ''; Write-Host '[1/2] Installing DLAA baseline + official ReShade...' -ForegroundColor Cyan
        $localCore=Join-Path (Split-Path -Parent $Self) 'core\Install-DLAA-Core.bat'
        if (-not (Test-Path -LiteralPath $localCore)) { $localCore=Join-Path (Split-Path -Parent $Self) 'Install-DLAA-Core.bat' }
        if (-not (Test-Path -LiteralPath $localCore)) { Fail 'Install-DLAA-Core.bat is missing from the installer package.' }
        $CoreTemp=Join-Path $Game '_GTAIV_DLSS_Install-DLAA-Core.bat'; Copy-Item -LiteralPath $localCore -Destination $CoreTemp -Force
        $coreText=[IO.File]::ReadAllText($CoreTemp); $coreText=$coreText.Replace("    Read-Host 'Press Enter to close'; exit 0",'    exit 0'); $coreText=$coreText.Replace("    Read-Host 'Press Enter to close'; exit 1",'    exit 1'); [IO.File]::WriteAllText($CoreTemp,$coreText,[Text.UTF8Encoding]::new($false))
        $p=Start-Process -FilePath $CoreTemp -WorkingDirectory $Game -Wait -PassThru; if($p.ExitCode -ne 0){Fail "DLAA installer failed with exit code $($p.ExitCode)."}
        Remove-Item -LiteralPath $CoreTemp -Force -ErrorAction SilentlyContinue; $CoreTemp=$null
    } else { Write-Host '[1/2] Existing DLAA baseline detected; skipping reinstall.' -ForegroundColor Green }

    Ensure-ReShade $Game $Trex
    if (-not (Has-PatchMarker $GlobalReShade)) {
        Write-Host ''; Write-Host '[2/2] Installing the project ReShade b-bridge input patch...' -ForegroundColor Cyan
        $patched=Join-Path $Temp 'ReShade64-bbridge.dll'; if($env:GTAIV_SETUP_RESHADE_PATCH -and (Test-Path -LiteralPath $env:GTAIV_SETUP_RESHADE_PATCH -PathType Leaf)){Write-Host 'Using local ReShade input patch beside setup EXE.' -ForegroundColor DarkGray;Copy-Item -LiteralPath $env:GTAIV_SETUP_RESHADE_PATCH -Destination $patched -Force}else{$patchedUrl=Resolve-ProjectAssetUrl $PatchedReShadeAsset;Download $patchedUrl $patched}; Assert-SHA256 $patched $PatchedReShadeHash
        if (-not (Has-PatchMarker $patched)) { Fail 'ReShade64-bbridge.dll is missing the expected patch marker.' }
        if (-not (Test-Path -LiteralPath $GlobalReShadeBackup)) { Copy-Item -LiteralPath $GlobalReShade -Destination $GlobalReShadeBackup -Force }
        Copy-Item -LiteralPath $patched -Destination $GlobalReShade -Force; Assert-SHA256 $GlobalReShade $PatchedReShadeHash
        $bridgeConf=Join-Path $Trex 'bridge.conf'; if (-not (Test-Path -LiteralPath $bridgeConf)) { Fail 'bridge.conf is missing.' }
        Set-KeyEquals $bridgeConf 'client.DirectInput.forward.mousePolicy' '3'; Set-KeyEquals $bridgeConf 'client.DirectInput.forward.keyboardPolicy' '3'
    } else { Write-Host '[2/2] System-wide ReShade input patch already active.' -ForegroundColor Green }
    if (-not (Has-PatchMarker $GlobalReShade)) { Fail 'Final ReShade input-patch verification failed.' }
    Write-Host ''; Write-Host 'DONE - DLAA + ReShade input patch installed.' -ForegroundColor Green; Write-Host 'Launch GTA IV once. Press Delete and confirm ReShade accepts mouse/keyboard input.' -ForegroundColor White
    Start-Sleep -Seconds 3; exit 0
} catch { $err=$_.Exception.Message; Write-Host ''; Write-Host ('INSTALL FAILED: '+$err) -ForegroundColor Red; Write-SetupResultIfEmpty $err; Read-Host 'Press Enter to close'; exit 1 }
finally { if($CoreTemp -and (Test-Path -LiteralPath $CoreTemp)){Remove-Item -LiteralPath $CoreTemp -Force -ErrorAction SilentlyContinue}; if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue} }
