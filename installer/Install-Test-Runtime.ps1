param(
    [Parameter(Mandatory=$true)][ValidateSet('Install','Restore')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Game,
    [string]$RuntimePackage = '',
    [string]$ResultFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$TestVersion = '1.2.10-test'
$RuntimeZipHash = '14D874F6ECD30E230655D0468383504D41BF90FD72FF5FC54E0A5A4EAD5EDEA3'
$script:Temp = $null

$ManagedFiles = @(
    'd3d9.dll',
    '.trex\NvRemixBridge.exe',
    '.trex\d3d9vk_x64.dll',
    '.trex\bridge.conf',
    '.trex\dlss5-feed.addon64',
    '.trex\nvngx_dlss.dll',
    '.trex\m3k\m3k-nvngx.dll',
    '.trex\reshade-shaders\Shaders\DLSS5_Feed.fx',
    '.trex\reshade-shaders\Shaders\M3K_Sharpen.fx',
    '.trex\reshade-shaders\Shaders\ReShade.fxh',
    '.trex\reshade-shaders\Shaders\ReShadeUI.fxh',
    '.trex\reshade-shaders\Shaders\DrawText.fxh',
    'GTAIV_SCALING_INSTALLED.txt'
)

function Write-Result([string]$Message) {
    if (-not $ResultFile) { return }
    try { [IO.File]::WriteAllText($ResultFile, $Message, [Text.UTF8Encoding]::new($false)) } catch {}
}
function Fail([string]$Message) { throw $Message }

function Normalize-GamePath([string]$Path) {
    $p = $Path.Trim().Trim('"')
    if ((Test-Path -LiteralPath $p -PathType Leaf) -and ([IO.Path]::GetFileName($p) -ieq 'GTAIV.exe')) {
        $p = Split-Path -Parent $p
    }
    if (Test-Path -LiteralPath (Join-Path $p 'GTAIV.exe') -PathType Leaf) {
        return (Resolve-Path -LiteralPath $p).Path
    }
    $nested = Join-Path $p 'GTAIV'
    if (Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe') -PathType Leaf) {
        return (Resolve-Path -LiteralPath $nested).Path
    }
    Fail 'GTAIV.exe was not found in the selected folder.'
}

function Get-ReceiptValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + '=(.*)$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Set-ReceiptValues([string]$Receipt, [string]$Backup) {
    $values = [ordered]@{
        Version = $TestVersion
        TestRuntime = $TestVersion
        TestRuntimeBackup = $Backup
    }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($line in [IO.File]::ReadAllLines($Receipt)) {
        if ($line -match '^([^=]+)=') {
            $key = $Matches[1]
            if ($values.Contains($key)) {
                [void]$lines.Add($key + '=' + $values[$key])
                $seen[$key] = $true
                continue
            }
        }
        [void]$lines.Add($line)
    }
    foreach ($key in $values.Keys) {
        if (-not $seen.ContainsKey($key)) {
            [void]$lines.Add($key + '=' + $values[$key])
        }
    }
    $temporary = $Receipt + '.test-runtime.tmp'
    [IO.File]::WriteAllLines($temporary, $lines.ToArray(), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Receipt -Force
}

function Set-KeyEquals([string]$Path, [string]$Key, [string]$Value) {
    $text = [IO.File]::ReadAllText($Path)
    $pattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*.*$'
    $line = $Key + ' = ' + $Value
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, $line)
    } else {
        $text = $text.TrimEnd([char]13,[char]10) + [Environment]::NewLine + $line + [Environment]::NewLine
    }
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Assert-SHA256([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "$Label is missing: $Path" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        Fail ($Label + ' SHA-256 mismatch.' + [Environment]::NewLine +
            'Expected: ' + $Expected + [Environment]::NewLine + 'Actual:   ' + $actual)
    }
}

function New-TestBackup([string]$Root) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $backup = Join-Path $Root ('_GTAIV_SCALING_TEST_BACKUP_' + $stamp)
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $present = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in $ManagedFiles) {
        $source = Join-Path $Root $relative
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $destination = Join-Path $backup $relative
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $source -Destination $destination -Force
            [void]$present.Add($relative)
        }
    }
    [IO.File]::WriteAllLines((Join-Path $backup 'present-files.txt'), $present.ToArray(), [Text.UTF8Encoding]::new($false))
    return $backup
}

function Test-TestBackup([string]$Root, [string]$Backup) {
    if (-not $Backup) { Fail 'The previous-runtime backup path is missing from the installation receipt.' }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $backupFull = [IO.Path]::GetFullPath($Backup)
    if (-not $backupFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        Fail 'The recorded test backup is outside the GTA IV folder. Refusing to restore it.'
    }
    $listPath = Join-Path $backupFull 'present-files.txt'
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) {
        Fail "The test backup is incomplete: $listPath is missing."
    }
    $present = @(Get-Content -LiteralPath $listPath)
    foreach ($relative in $present) {
        if ($relative -notin $ManagedFiles) { Fail "Unexpected path in backup manifest: $relative" }
        if (-not (Test-Path -LiteralPath (Join-Path $backupFull $relative) -PathType Leaf)) {
            Fail "The test backup is missing: $relative"
        }
    }
    return $present
}

function Restore-TestBackup([string]$Root, [string]$Backup) {
    $present = @(Test-TestBackup $Root $Backup)
    $presentSet = @{}
    foreach ($relative in $present) { $presentSet[$relative] = $true }
    foreach ($relative in $ManagedFiles) {
        $destination = Join-Path $Root $relative
        if ($presentSet.ContainsKey($relative)) {
            $source = Join-Path $Backup $relative
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
}

function Get-RuntimeTemp {
    if (-not $script:Temp) {
        $script:Temp = Join-Path $env:TEMP ('GTAIV_SCALING_TEST_' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null
    }
    return $script:Temp
}

function Expand-AndVerifyRuntime([string]$Package) {
    if (-not $Package -or -not (Test-Path -LiteralPath $Package -PathType Leaf)) {
        Fail 'The bundled test runtime ZIP is missing.'
    }
    Assert-SHA256 $Package $RuntimeZipHash 'GTA IV Scaling test runtime ZIP'
    $destination = Join-Path (Get-RuntimeTemp) 'runtime'
    Expand-Archive -LiteralPath $Package -DestinationPath $destination -Force
    $manifest = Join-Path $destination 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Fail 'Runtime SHA256SUMS.txt is missing.' }

    $expected = @{}
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line -match '^([A-Fa-f0-9]{64})\s{2}(.+)$') {
            $relative = $Matches[2].Replace('/', '\')
            $expected[$relative] = $Matches[1].ToUpperInvariant()
        }
    }
    if ($expected.Count -lt 10) { Fail 'Runtime checksum manifest is incomplete.' }
    foreach ($relative in $expected.Keys) {
        Assert-SHA256 (Join-Path $destination $relative) $expected[$relative] $relative
    }

    foreach ($required in @(
        'd3d9.dll', 'NvRemixBridge.exe', 'd3d9vk_x64.dll', 'bridge.conf',
        'dlss5-feed.addon64', 'dxvk.conf', 'nvngx_dlss.dll',
        'm3k\m3k-nvngx.dll', 'DLSS5_Feed.fx', 'M3K_Sharpen.fx',
        'ReShade.fxh', 'ReShadeUI.fxh', 'DrawText.fxh'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $destination $required) -PathType Leaf)) {
            Fail "Test runtime is missing required file: $required"
        }
    }

    $client = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $destination 'd3d9.dll')))
    if (-not $client.Contains('[M3K-DI-KEY]')) { Fail 'Test runtime d3d9.dll does not contain the DirectInput fix marker.' }
    if (-not $client.Contains('M3K-BBRIDGE-RELAY-ACK-HOOK')) { Fail 'Test runtime d3d9.dll does not contain the verified b-bridge relay hook.' }
    if (-not $client.Contains('M3K-BRIDGE-INPUT-TRACE')) { Fail 'Test runtime d3d9.dll does not contain the Home/F11 forwarding trace.' }
    if (-not $client.Contains('M3K-STEAM-INPUT')) { Fail 'Test runtime d3d9.dll does not contain the Steam F11 input trace.' }
    $presenter = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $destination 'd3d9vk_x64.dll')))
    if (-not $presenter.Contains('[M3K-VIEWPORT-RT]')) { Fail 'Test runtime presenter does not contain the viewport diagnostic marker.' }
    return $destination
}

function Install-TestRuntime([string]$Root, [string]$Package) {
    $receipt = Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        Fail 'This test installer requires an existing GTA IV Scaling v1.2.9 installation.'
    }

    foreach ($required in @(
        'dinput8.dll', 'd3d9.dll', '.trex\NvRemixBridge.exe',
        '.trex\d3d9vk_x64.dll', '.trex\bridge.conf',
        '.trex\dlss5-feed.addon64', '.trex\nvngx_dlss.dll',
        '.trex\ReShade.ini'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $required) -PathType Leaf)) {
            Fail "The existing v1.2.9 installation is incomplete; missing $required. No runtime files were changed."
        }
    }

    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before installing the test runtime.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before installing the test runtime.' }

    $receiptText = [IO.File]::ReadAllText($receipt)
    $version = Get-ReceiptValue $receiptText 'Version'
    $backup = ''
    if ($version -eq '1.2.9') {
        $backup = New-TestBackup $Root
    } elseif ($version -eq $TestVersion) {
        $backup = Get-ReceiptValue $receiptText 'TestRuntimeBackup'
        [void](Test-TestBackup $Root $backup)
    } else {
        Fail "This test installer supports GTA IV Scaling v1.2.9 only. Detected receipt version: $version"
    }

    $runtime = Expand-AndVerifyRuntime $Package
    $installStarted = $false
    try {
        $copyMap = [ordered]@{
            'd3d9.dll' = 'd3d9.dll'
            'NvRemixBridge.exe' = '.trex\NvRemixBridge.exe'
            'd3d9vk_x64.dll' = '.trex\d3d9vk_x64.dll'
            'dlss5-feed.addon64' = '.trex\dlss5-feed.addon64'
            'nvngx_dlss.dll' = '.trex\nvngx_dlss.dll'
            'm3k\m3k-nvngx.dll' = '.trex\m3k\m3k-nvngx.dll'
            'DLSS5_Feed.fx' = '.trex\reshade-shaders\Shaders\DLSS5_Feed.fx'
            'M3K_Sharpen.fx' = '.trex\reshade-shaders\Shaders\M3K_Sharpen.fx'
            'ReShade.fxh' = '.trex\reshade-shaders\Shaders\ReShade.fxh'
            'ReShadeUI.fxh' = '.trex\reshade-shaders\Shaders\ReShadeUI.fxh'
            'DrawText.fxh' = '.trex\reshade-shaders\Shaders\DrawText.fxh'
        }

        $installStarted = $true
        foreach ($entry in $copyMap.GetEnumerator()) {
            $source = Join-Path $runtime $entry.Key
            $destination = Join-Path $Root $entry.Value
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }

        # Preserve the user's existing bridge.conf settings; change only the
        # three forwarding/frame-cap values required by the project installer.
        $bridgeConf = Join-Path $Root '.trex\bridge.conf'
        Set-KeyEquals $bridgeConf 'clientFrameCap' '0'
        Set-KeyEquals $bridgeConf 'client.DirectInput.forward.mousePolicy' '3'
        Set-KeyEquals $bridgeConf 'client.DirectInput.forward.keyboardPolicy' '3'

        $installedClient = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $Root 'd3d9.dll')))
        $installedPresenter = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $Root '.trex\d3d9vk_x64.dll')))
        if (-not $installedClient.Contains('[M3K-DI-KEY]')) { Fail 'Installed client verification failed.' }
        if (-not $installedClient.Contains('M3K-BBRIDGE-RELAY-ACK-HOOK')) { Fail 'Installed b-bridge relay hook verification failed.' }
        if (-not $installedClient.Contains('M3K-BRIDGE-INPUT-TRACE')) { Fail 'Installed Home/F11 forwarding trace verification failed.' }
        if (-not $installedClient.Contains('M3K-STEAM-INPUT')) { Fail 'Installed Steam F11 input trace verification failed.' }
        if (-not $installedPresenter.Contains('[M3K-VIEWPORT-RT]')) { Fail 'Installed presenter verification failed.' }

        Set-ReceiptValues $receipt $backup
        Write-Host "Installed test runtime. Previous runtime backup: $backup" -ForegroundColor Green
        Write-Result "GTA IV Scaling 1.2.10 test runtime installed. Previous runtime backup: $backup"
    } catch {
        $failure = $_.Exception.Message
        if ($installStarted) {
            try {
                Restore-TestBackup $Root $backup
                Write-Warning 'The install failed; the previous runtime was restored automatically.'
            } catch {
                $failure += ' Automatic rollback also failed: ' + $_.Exception.Message
            }
        }
        throw $failure
    }
}

function Restore-TestRuntime([string]$Root) {
    $receipt = Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        Fail 'GTA IV Scaling installation receipt was not found.'
    }
    $receiptText = [IO.File]::ReadAllText($receipt)
    if ((Get-ReceiptValue $receiptText 'Version') -ne $TestVersion) {
        Fail 'The 1.2.10 test runtime is not installed, so there is nothing to restore.'
    }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before restoring the previous runtime.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before restoring the previous runtime.' }
    $backup = Get-ReceiptValue $receiptText 'TestRuntimeBackup'
    Restore-TestBackup $Root $backup
    Write-Host "Restored the previous runtime from: $backup" -ForegroundColor Green
    Write-Result "Previous GTA IV Scaling runtime restored. Backup retained at: $backup"
}

try {
    $Game = Normalize-GamePath $Game
    if ($Action -eq 'Install') {
        Install-TestRuntime $Game $RuntimePackage
    } else {
        Restore-TestRuntime $Game
    }
} catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('TEST RUNTIME SETUP FAILED: ' + $message) -ForegroundColor Red
    Write-Result $message
    exit 1
} finally {
    if ($script:Temp -and (Test-Path -LiteralPath $script:Temp)) {
        Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
