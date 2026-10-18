param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('INSTALL','UPDATE_NR','UPDATE_FUSIONFIX','REMOVE_KEEP_FUSIONFIX','REMOVE_ALL')]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$Game,

    [string]$ReShadeSetup = '',
    [string]$NrPackage = '',
    [Parameter(Mandatory=$true)]
    [string]$RuntimePackage,
    [Parameter(Mandatory=$true)]
    [string]$ReShadePatch,
    [string]$ResultFile = ''
)

$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.2.6'
$RuntimeHash='__SCALING_RUNTIME_SHA256__'
$FeederHash='__SCALING_FEEDER_SHA256__'
$ReShadePatchHash='D5BD8CB2B6E935506888EA71711361B9AFCD72ED7C70926C0F52E8F8E47C7510'
$Nr40DllHash='4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'
$Nr50DllHash='E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$NrSfDllHash='6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927'
$Nr40ZipHash='46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F'
$Nr50ZipHash='388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC'
$NrSfZipHash='1DA35941894994EB087E017577829E492454E9BAE3A6A9397027069CEB74955C'
$LumeniteHash='572FEFB20D466AFE50998E16996B4833BEC675264485C99FE768A2337636E756'
$script:Temp=$null

function Write-Result([string]$Text){
    if(-not $ResultFile){return}
    try{[IO.File]::WriteAllText($ResultFile,$Text,[Text.UTF8Encoding]::new($false))}catch{}
}
function Fail([string]$Text){throw $Text}
function Assert-SHA256([string]$Path,[string]$Expected,[string]$Label){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail "$Label is missing: $Path"}
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
    if($actual -ne $Expected.ToUpperInvariant()){Fail "$Label SHA256 mismatch. Expected: $Expected Actual: $actual"}
}
function Normalize-GamePath([string]$Path){
    $p=$Path.Trim().Trim('"')
    if((Test-Path -LiteralPath $p -PathType Leaf)-and([IO.Path]::GetFileName($p)-ieq'GTAIV.exe')){$p=Split-Path -Parent $p}
    if(Test-Path -LiteralPath (Join-Path $p 'GTAIV.exe')){return (Resolve-Path -LiteralPath $p).Path}
    $nested=Join-Path $p 'GTAIV'
    if(Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe')){return (Resolve-Path -LiteralPath $nested).Path}
    Fail 'GTAIV.exe was not found in the selected folder.'
}
function Download-GitHubUrl([string]$Uri,[string]$Destination,[string]$Label){
    Write-Host "Downloading $Label..." -ForegroundColor Cyan
    $headers=@{'User-Agent'='GTA-IV-Scaling-Setup'}
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $Uri -OutFile $Destination
    if(-not(Test-Path -LiteralPath $Destination)){Fail "$Label download did not produce a file."}
}
function Download-GitHubReleaseAsset([string]$Repo,[string]$Tag,[string]$Asset,[string]$Destination,[string]$Label){
    $headers=@{'User-Agent'='GTA-IV-Scaling-Setup'}
    $release=Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    $match=@($release.assets|Where-Object{$_.name -eq $Asset})|Select-Object -First 1
    if(-not $match -or -not $match.browser_download_url){Fail "GitHub release asset not found: $Repo / $Tag / $Asset"}
    Download-GitHubUrl ([string]$match.browser_download_url) $Destination $Label
    return $Destination
}
function Get-AutoTemp{
    if(-not $script:Temp){
        $script:Temp=Join-Path $env:TEMP ('GTAIV_SCALING_126_'+[Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Temp -Force|Out-Null
    }
    return $script:Temp
}
function Get-GpuInfo{
    $all=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $rtx=@($all|Where-Object{$_.Name -match '(?i)NVIDIA.*RTX'}|Select-Object -First 1)
    $name=if($rtx){[string]$rtx.Name}elseif($all.Count){[string]$all[0].Name}else{'Unknown GPU'}
    $series=0
    $isRtx=$false
    if($rtx){
        $isRtx=$true
        if($name -match '(?i)RTX\s*(20|30|40|50)'){$series=[int]$Matches[1]}
    }
    return [pscustomobject]@{Name=$name;IsRtx=$isRtx;Series=$series}
}
function Test-FusionFixFirstRun([string]$Root){
    $cfg='GTAIV.EFLC.FusionFix.cfg'
    foreach($p in @(
        (Join-Path $Root "plugins\$cfg"),
        (Join-Path $Root $cfg),
        (Join-Path $env:LOCALAPPDATA "Rockstar Games\GTA IV\$cfg"),
        (Join-Path $env:LOCALAPPDATA "GTAIV.EFLC.FusionFix\$cfg"),
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "GTAIV.EFLC.FusionFix\$cfg")
    )){if(Test-Path -LiteralPath $p){return $true}}
    return $false
}
function Resolve-FusionFixPackage{
    $dest=Join-Path (Get-AutoTemp) 'GTAIV.EFLC.FusionFix.zip'
    return Download-GitHubReleaseAsset 'ThirteenAG/GTAIV.EFLC.FusionFix' 'v5.0.1' 'GTAIV.EFLC.FusionFix.zip' $dest 'FusionFix 5.0.1'
}
function Install-FusionFix([string]$Root){
    $zip=Resolve-FusionFixPackage
    Assert-SHA256 $zip '3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41' 'FusionFix package'
    $out=Join-Path (Get-AutoTemp) 'fusionfix'
    Expand-Archive -LiteralPath $zip -DestinationPath $out -Force
    $dinput=Get-ChildItem -LiteralPath $out -Recurse -File -Filter 'dinput8.dll'|Select-Object -First 1
    if(-not $dinput){Fail 'FusionFix package did not contain dinput8.dll.'}
    Get-ChildItem -LiteralPath $dinput.Directory.FullName -Force|ForEach-Object{
        Copy-Item -LiteralPath $_.FullName -Destination $Root -Recurse -Force
    }
    if(-not(Test-Path -LiteralPath (Join-Path $Root 'dinput8.dll'))){Fail 'FusionFix installation did not produce dinput8.dll.'}
}
function Resolve-LumenitePackage{
    $dest=Join-Path (Get-AutoTemp) 'LumeniteFX.zip'
    Download-GitHubUrl 'https://api.github.com/repos/umar-afzaal/LumeniteFX/zipball/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9' $dest 'pinned LumeniteFX'
    Assert-SHA256 $dest $LumeniteHash 'LumeniteFX package'
    return $dest
}
function Test-Foundation([string]$Root){
    $trex=Join-Path $Root '.trex'
    return (Test-Path -LiteralPath (Join-Path $Root 'd3d9.dll')) -and
           (Test-Path -LiteralPath (Join-Path $trex 'NvRemixBridge.exe')) -and
           (Test-Path -LiteralPath (Join-Path $trex 'd3d9vk_x64.dll')) -and
           (Test-Path -LiteralPath (Join-Path $trex 'dlss5-feed.addon64')) -and
           (Test-Path -LiteralPath (Join-Path $trex 'ReShade.ini'))
}
function Prepare-Bat([string]$Path,[string]$Root){
    $text=[IO.File]::ReadAllText($Path)
    $text=$text.Replace('$Game = Resolve-GameFolder','$Game = $env:GTAIV_SETUP_GAME')
    $text=$text.Replace('$ok = Read-Host ''Continue? [Y/n]''','$ok = ''y''')
    $text=$text.Replace('$ok = Read-Host ''Continue? [y/N]''','$ok = ''y''')
    $text=$text.Replace('Read-Host ''Press Enter to close''','$null = $null')
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
    $env:GTAIV_SETUP_GAME=$Root
}
function Invoke-Bat([string]$Path,[string]$Root,[switch]$NonInteractive){
    if(-not(Test-Path -LiteralPath $Path)){Fail "Installer component missing: $Path"}
    if($NonInteractive){Prepare-Bat $Path $Root}
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$env:ComSpec
    $psi.Arguments='/d /c call "'+$Path+'"'
    $psi.WorkingDirectory=$Root
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$false
    if($NonInteractive){$psi.EnvironmentVariables['GTAIV_SETUP_GAME']=$Root}
    foreach($name in @('GTAIV_SETUP_RESHADE','GTAIV_SETUP_LUMENITE','GTAIV_SETUP_PROJECT_RUNTIME','GTAIV_SETUP_RESHADE_PATCH','GTAIV_SETUP_RESULT_FILE')){
        $v=[Environment]::GetEnvironmentVariable($name)
        if($v){$psi.EnvironmentVariables[$name]=$v}
    }
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    if(-not $p.Start()){Fail "Could not start $Path"}
    $p.WaitForExit();$code=$p.ExitCode;$p.Dispose()
    if($code-ne 0){Fail "Installer component failed with exit code ${code}: $([IO.Path]::GetFileName($Path))"}
}
function Set-Ini([string]$Path,[string]$Section,[string]$Key,[string]$Value){
    $list=New-Object 'System.Collections.Generic.List[string]'
    if(Test-Path -LiteralPath $Path){Get-Content -LiteralPath $Path|ForEach-Object{[void]$list.Add([string]$_)}}
    $sec="[$Section]";$start=-1
    for($i=0;$i-lt$list.Count;$i++){if($list[$i].Trim()-ieq$sec){$start=$i;break}}
    if($start-lt0){
        if($list.Count){[void]$list.Add('')}
        [void]$list.Add($sec);[void]$list.Add("$Key=$Value")
    }else{
        $end=$list.Count
        for($i=$start+1;$i-lt$list.Count;$i++){if($list[$i]-match '^\s*\[.+\]\s*$'){$end=$i;break}}
        $found=$false
        for($i=$start+1;$i-lt$end;$i++){
            if($list[$i]-match ('^\s*'+[regex]::Escape($Key)+'\s*=')){$list[$i]="$Key=$Value";$found=$true;break}
        }
        if(-not $found){$list.Insert($start+1,"$Key=$Value")}
    }
    [IO.File]::WriteAllLines($Path,$list,[Text.UTF8Encoding]::new($false))
}
function Get-Ini([string]$Path,[string]$Section,[string]$Key){
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    $inside=$false
    foreach($line in Get-Content -LiteralPath $Path){
        $t=$line.Trim()
        if($t -match '^\[(.+)\]$'){$inside=($Matches[1]-ieq$Section);continue}
        if($inside -and $t -match ('^'+[regex]::Escape($Key)+'\s*=\s*(.*)$')){return $Matches[1].Trim()}
    }
    return $null
}
function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value){
    $text=if(Test-Path -LiteralPath $Path){[IO.File]::ReadAllText($Path)}else{''}
    $pat='(?m)^\s*'+[regex]::Escape($Key)+'\s*=\s*.*$';$line="$Key = $Value"
    if($text-match$pat){$text=[regex]::Replace($text,$pat,$line)}
    else{
        if($text.Length-and-not$text.EndsWith([Environment]::NewLine)){$text+=[Environment]::NewLine}
        $text+=$line+[Environment]::NewLine
    }
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}
# b-bridge 0.1.0 filtered out non-16:9 monitor modes. Preserve
# modeCountCompatibility, which protects GTA IV's fixed-size mode array.
function Remove-DxvkForcedAspectRatio([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail "DXVK configuration is missing: $Path"}
    $text=[IO.File]::ReadAllText($Path)
    $pattern='(?im)^[ \t]*d3d9\.forceAspectRatio[ \t]*=[^\r\n]*(?:\r?\n|$)'
    $patched=[regex]::Replace($text,$pattern,'')
    if($patched-ne$text){
        [IO.File]::WriteAllText($Path,$patched,[Text.UTF8Encoding]::new($false))
        Write-Host 'Removed obsolete DXVK 16:9 aspect-ratio filter.' -ForegroundColor Green
    }
    if([regex]::IsMatch([IO.File]::ReadAllText($Path),'(?im)^[ \t]*d3d9\.forceAspectRatio[ \t]*=')){
        Fail 'DXVK aspect-ratio filter still active after repair.'
    }
}

# Fast upgrade from an intact 1.2.2 install: touch only dxvk.conf and the
# receipt, preserving all existing DLAA/DLSS/FSR binaries and profiles.
function Repair-V122AspectRatio([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    $config=Join-Path $Root 'dxvk.conf'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf) -or
       -not(Test-Path -LiteralPath $config -PathType Leaf) -or
       -not(Test-Foundation $Root) -or
       -not(Test-Path -LiteralPath (Join-Path $Root '.trex\m3k-nr.ini'))){return $false}
    $before=[IO.File]::ReadAllText($receipt)
    if($before -notmatch '(?m)^Version=1\.2\.[234]'){return $false}
    $backup=Join-Path $Root ('_GTAIV_SCALING_PRE123_BACKUP_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    Copy-Item -LiteralPath $receipt -Destination (Join-Path $backup 'GTAIV_SCALING_INSTALLED.txt') -Force
    Copy-Item -LiteralPath $config -Destination (Join-Path $backup 'dxvk.conf') -Force
    Remove-DxvkForcedAspectRatio $config
    $after=[regex]::Replace($before,'(?m)^Version=1\.2\.[234](?=\r?$)','Version=1.2.6')
    if($after-eq$before){Fail 'Cannot update legacy receipt after DXVK repair.'}
    $after=$after.TrimEnd([char]13,[char]10)+[Environment]::NewLine+
           'AspectRatioFix=DXVK forced 16:9 filter removed'+[Environment]::NewLine+
           "Pre125Backup=$backup"+[Environment]::NewLine
    [IO.File]::WriteAllText($receipt,$after,[Text.UTF8Encoding]::new($false))
    Write-Host 'GTA IV Scaling -> 1.2.6 configuration-only upgrade complete.' -ForegroundColor Green
    Write-Host 'Existing DLAA/DLSS/FSR files and scaling settings were preserved.' -ForegroundColor Green
    return $true
}

function Ensure-Technique([string]$Path,[string]$Technique){
    if(-not(Test-Path -LiteralPath $Path)){return}
    $text=[IO.File]::ReadAllText($Path)
    foreach($key in @('Techniques','TechniqueSorting')){
        $pat='(?m)^'+[regex]::Escape($key)+'=(.*)$';$m=[regex]::Match($text,$pat)
        if($m.Success){
            $items=@($m.Groups[1].Value.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_})
            if($items -notcontains $Technique){$items+= $Technique}
            $line=$key+'='+($items -join ',')
            $text=$text.Substring(0,$m.Index)+$line+$text.Substring($m.Index+$m.Length)
        }
    }
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}
function Resolve-NrDll([object]$Gpu,[string]$OwnPath){
    if($Gpu.Series -notin @(20,30,40,50)){return $null}
    if($OwnPath){
        $dll=(Resolve-Path -LiteralPath $OwnPath).Path
    }else{
        if($Gpu.Series-in@(20,30)){$tag='dlssnr-310.8.SF-v2';$asset='nvngx_dlssnr_310.8.SF-v2.zip';$expectedZip=$NrSfZipHash}
        elseif($Gpu.Series-eq40){$tag='dlssnr-310.8.0-RTX40';$asset='nvngx_dlssnr_310.8.0-RTX40.zip';$expectedZip=$Nr40ZipHash}
        else{$tag='dlssnr-310.8.0';$asset='nvngx_dlssnr_310.8.0.zip';$expectedZip=$Nr50ZipHash}
        $zip=Join-Path (Get-AutoTemp) $asset
        Download-GitHubReleaseAsset 'RankFTW/rhi-repo' $tag $asset $zip 'DLSS Neural Rendering'
        Assert-SHA256 $zip $expectedZip 'Neural Rendering ZIP'
        $out=Join-Path (Get-AutoTemp) 'nr'
        Expand-Archive -LiteralPath $zip -DestinationPath $out -Force
        $found=@(Get-ChildItem -LiteralPath $out -Recurse -File -Filter 'nvngx_dlssnr.dll')
        if($found.Count-ne1){Fail "Expected one nvngx_dlssnr.dll, found $($found.Count)."}
        $dll=$found[0].FullName
    }
    $expected=if($Gpu.Series-in@(20,30)){$NrSfDllHash}elseif($Gpu.Series-eq40){$Nr40DllHash}else{$Nr50DllHash}
    Assert-SHA256 $dll $expected 'Neural Rendering DLL'
    if($Gpu.Series-eq50){
        $sig=Get-AuthenticodeSignature -LiteralPath $dll
        if($sig.Status-ne'Valid'-or$sig.SignerCertificate.Subject-notmatch'NVIDIA'){Fail 'RTX 50 Neural Rendering DLL signature is invalid.'}
    }
    return $dll
}
function Backup-ScalingFiles([string]$Root){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $dest=Join-Path $Root ("_GTAIV_SCALING_PRE123_BACKUP_"+$stamp)
    New-Item -ItemType Directory -Path $dest -Force|Out-Null
    foreach($rel in @('d3d9.dll','dxvk.conf','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\bridge.conf','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\nvngx_dlss.dll','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')){
        $src=Join-Path $Root $rel
        if(Test-Path -LiteralPath $src){
            $dst=Join-Path $dest $rel;$parent=Split-Path -Parent $dst
            if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
    return $dest
}

function Invoke-NrUpdate([string]$Root,[string]$Local){
    $tool=Join-Path $PSScriptRoot 'Update-NR.ps1'
    if(-not(Test-Path -LiteralPath $tool -PathType Leaf)){Fail 'NR updater missing from setup.'}
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$tool,'-Game',$Root)
    if($Local){$arguments+=@('-LocalPackage',$Local)}
    & powershell.exe @arguments
    if($LASTEXITCODE-ne0){Fail 'NR update failed; the installed NR DLL was preserved. See console for details.'}
}
function Upgrade-AddonUi([string]$Root){
    # On a config-only upgrade the new ReShade add-on still needs deploying.
    Assert-SHA256 $RuntimePackage $RuntimeHash 'GTA IV Scaling runtime'
    $destination=Join-Path $Root '.trex\dlss5-feed.addon64'
    if(-not(Test-Path -LiteralPath (Split-Path -Parent $destination))){Fail 'Scaling add-on folder missing'}
    $extract=Join-Path (Get-AutoTemp) 'v125-addon'
    Expand-Archive -LiteralPath $RuntimePackage -DestinationPath $extract -Force
    $candidate=Join-Path $extract 'dlss5-feed.addon64'
    Assert-SHA256 $candidate $FeederHash 'v1.2.6 ReShade add-on'
    $backup=Join-Path $Root ('.trex\_v125_addon_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if(Test-Path -LiteralPath $destination){Copy-Item -LiteralPath $destination -Destination (Join-Path $backup 'dlss5-feed.addon64') -Force}
    try{
        Copy-Item -LiteralPath $candidate -Destination $destination -Force
        Assert-SHA256 $destination $FeederHash 'installed v1.2.6 ReShade add-on'
    }catch{
        $old=Join-Path $backup 'dlss5-feed.addon64'
        if(Test-Path -LiteralPath $old){Copy-Item -LiteralPath $old -Destination $destination -Force}
        throw
    }
}
function TryAutoNrUpdate([string]$Root,[string]$Local){
    try{Invoke-NrUpdate $Root $Local}
    catch{
        if($Local){throw}
        Write-Warning ('Could not update NR automatically: '+$_.Exception.Message)
        Write-Warning 'Existing NR runtime remains usable. Run Update Neural Rendering Only later or supply a local DLL.'
    }
}

function Invoke-LatestFusionFix([string]$Root){
    $script=Join-Path $PSScriptRoot 'Install-Latest-FusionFix.ps1'
    if(-not(Test-Path -LiteralPath $script -PathType Leaf)){Fail 'FusionFix updater missing from setup payload.'}
    $arguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Game',$Root)
    if($ResultFile){$arguments+=@('-ResultFile',$ResultFile)}
    & powershell.exe @arguments
    if($LASTEXITCODE -ne 0){Fail 'Could not install or update latest FusionFix. Existing files were preserved or restored; see setup output.'}
}

function Install-Scaling([string]$Root){
    Assert-SHA256 $RuntimePackage $RuntimeHash 'GTA IV Scaling runtime'
    Assert-SHA256 $ReShadePatch $ReShadePatchHash 'ReShade input patch'
    $gpu=Get-GpuInfo
    Write-Host "Detected GPU: $($gpu.Name)" -ForegroundColor Cyan
    if($gpu.IsRtx){Write-Host 'Runtime capability: NVIDIA DLAA/DLSS + AMD FidelityFX FSR' -ForegroundColor Green}
    else{Write-Host 'Runtime capability: AMD FidelityFX FSR (NVIDIA option hidden)' -ForegroundColor Green}

    if(Get-Process GTAIV -ErrorAction SilentlyContinue){Fail 'Close GTA IV before installing.'}
    if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}
    $hasFusionFix=Test-Path -LiteralPath (Join-Path $Root 'dinput8.dll') -PathType Leaf
    # Every Install / Repair first checks the official stable FusionFix release.
    # The updater compares receipts, preserves settings, backs up replaced files,
    # and stops rather than silently falling back to pinned 5.0.1.
    Invoke-LatestFusionFix $Root
    if(-not $hasFusionFix){
        Write-Result 'Latest stable FusionFix installed. Launch GTA IV to the main menu once, close it, then run this GTA IV Scaling installer again.'
        exit 20
    }
    if(-not(Test-FusionFixFirstRun $Root)){Fail 'FusionFix has not completed its first run. Launch GTA IV once to the main menu, close it, then rerun setup.'}

    if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}

    if(-not(Test-Foundation $Root)){
        if(-not $ReShadeSetup -or -not(Test-Path -LiteralPath $ReShadeSetup -PathType Leaf)){Fail 'Select the official ReShade 6.8.0 Full Add-On installer.'}
        $lum=Resolve-LumenitePackage
        $env:GTAIV_SETUP_RESHADE=(Resolve-Path -LiteralPath $ReShadeSetup).Path
        $env:GTAIV_SETUP_LUMENITE=$lum
        $env:GTAIV_SETUP_PROJECT_RUNTIME=(Resolve-Path -LiteralPath $RuntimePackage).Path
        $env:GTAIV_SETUP_RESHADE_PATCH=(Resolve-Path -LiteralPath $ReShadePatch).Path
        if($ResultFile){$env:GTAIV_SETUP_RESULT_FILE=$ResultFile}
        $foundation=Join-Path $PSScriptRoot 'Install-DLAA.bat'
        Invoke-Bat $foundation $Root -NonInteractive
    }

    $backup=Backup-ScalingFiles $Root
    $trex=Join-Path $Root '.trex'
    $runtimeDir=Join-Path (Get-AutoTemp) 'runtime'
    Expand-Archive -LiteralPath $RuntimePackage -DestinationPath $runtimeDir -Force
    Assert-SHA256 (Join-Path $runtimeDir 'dlss5-feed.addon64') $FeederHash 'GTA IV Scaling feeder'

    New-Item -ItemType Directory -Path $trex -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $trex 'm3k') -Force|Out-Null
    $shaderDir=Join-Path $trex 'reshade-shaders\Shaders'
    New-Item -ItemType Directory -Path $shaderDir -Force|Out-Null

    Copy-Item (Join-Path $runtimeDir 'd3d9.dll') (Join-Path $Root 'd3d9.dll') -Force
    foreach($name in @('NvRemixBridge.exe','d3d9vk_x64.dll','bridge.conf','dlss5-feed.addon64','nvngx_dlss.dll')){
        Copy-Item (Join-Path $runtimeDir $name) (Join-Path $trex $name) -Force
    }
    Copy-Item (Join-Path $runtimeDir 'dxvk.conf') (Join-Path $Root 'dxvk.conf') -Force
    Copy-Item (Join-Path $runtimeDir 'm3k\m3k-nvngx.dll') (Join-Path $trex 'm3k\m3k-nvngx.dll') -Force
    foreach($name in @('DLSS5_Feed.fx','M3K_Sharpen.fx','ReShade.fxh','ReShadeUI.fxh','DrawText.fxh')){
        Copy-Item (Join-Path $runtimeDir $name) (Join-Path $shaderDir $name) -Force
    }
    Set-KeyEquals (Join-Path $Root 'dxvk.conf') 'd3d9.samplerLodBias' '0.0'
    Remove-DxvkForcedAspectRatio (Join-Path $Root 'dxvk.conf')
    Set-KeyEquals (Join-Path $trex 'bridge.conf') 'clientFrameCap' '0'
    Set-KeyEquals (Join-Path $trex 'bridge.conf') 'client.DirectInput.forward.mousePolicy' '3'
    Set-KeyEquals (Join-Path $trex 'bridge.conf') 'client.DirectInput.forward.keyboardPolicy' '3'
    Set-KeyEquals (Join-Path $trex 'dlss5-feed.cfg') 'enabled' '1'
    Set-KeyEquals (Join-Path $trex 'dlss5-feed.cfg') 'mode' '2'
    Set-KeyEquals (Join-Path $trex 'dlss5-feed.cfg') 'work_resolution' '100'
    Ensure-Technique (Join-Path $trex 'ReShadePreset.ini') 'M3K_Sharpen@M3K_Sharpen.fx'

    $nrDest=Join-Path $trex 'm3k\nvngx_dlssnr.dll'
    $latestHashes=@(
      'CDFA6C1EC784867182164C7836F324F087B5C9F374D0C9FE46F54999FEABF3ED',
      '2BC19BC09A7B89DD44F73E2AC0108FCC586E2154BDD0830F242F4F040E28789F'
    )
    $keepLatest=(Test-Path -LiteralPath $nrDest -PathType Leaf) -and
      ((Get-FileHash -LiteralPath $nrDest -Algorithm SHA256).Hash.ToUpperInvariant() -in $latestHashes)
    if($gpu.Series-in@(20,30,40,50)){
        if(-not $keepLatest){
            $oldLocal=if($NrPackage -and $NrPackage.EndsWith('.dll',[StringComparison]::OrdinalIgnoreCase)){
                $candidateHash=(Get-FileHash -LiteralPath $NrPackage -Algorithm SHA256).Hash.ToUpperInvariant()
                if($candidateHash -notin $latestHashes){$NrPackage}else{''}
            }else{''}
            $nr=Resolve-NrDll $gpu $oldLocal
            Copy-Item -LiteralPath $nr -Destination $nrDest -Force
        }else{Write-Host 'Preserving already-installed verified 310.9.16 NR DLL.'}
    }elseif(Test-Path -LiteralPath $nrDest){
        Remove-Item -LiteralPath $nrDest -Force
    }

    $ini=Join-Path $trex 'm3k-nr.ini'
    $existingTech=Get-Ini $ini 'M3K' 'ScalingTechnology'
    if(-not $gpu.IsRtx){$tech='2'}
    elseif($existingTech-in@('0','1','2')){$tech=$existingTech}
    else{$tech='1'}

    Set-Ini $ini 'M3K' 'NvidiaRtxAvailable' $(if($gpu.IsRtx){'1'}else{'0'})
    Set-Ini $ini 'M3K' 'ScalingTechnology' $tech
    Set-Ini $ini 'M3K' 'SRProof' $(if($tech-eq'1'){'1'}else{'0'})
    Set-Ini $ini 'M3K' 'FSRProof' $(if($tech-eq'2'){'1'}else{'0'})
    if(-not(Get-Ini $ini 'M3K' 'MasterEnabled')){Set-Ini $ini 'M3K' 'MasterEnabled' '1'}
    if(-not(Get-Ini $ini 'M3K' 'LastSRProfile')){Set-Ini $ini 'M3K' 'LastSRProfile' '2'}
    if(-not(Get-Ini $ini 'M3K' 'SRProfile')){Set-Ini $ini 'M3K' 'SRProfile' '2'}
    if(-not(Get-Ini $ini 'M3K' 'CustomScalePercent')){Set-Ini $ini 'M3K' 'CustomScalePercent' '77'}
    if(-not(Get-Ini $ini 'M3K' 'FSRScalePermille')){Set-Ini $ini 'M3K' 'FSRScalePermille' '667'}
    if(-not(Get-Ini $ini 'M3K' 'FSRSharpness')){Set-Ini $ini 'M3K' 'FSRSharpness' '0.000'}
    if(-not(Get-Ini $ini 'M3K' 'JitterMode')){Set-Ini $ini 'M3K' 'JitterMode' '8'}
    if(-not(Get-Ini $ini 'M3K' 'NvidiaJitterCompMode')){Set-Ini $ini 'M3K' 'NvidiaJitterCompMode' '1'}
    Set-Ini $ini 'M3K' 'TemporalJitter' '1'
    if(-not(Get-Ini $ini 'M3K' 'LastNRMode')){Set-Ini $ini 'M3K' 'LastNRMode' '0'}
    if(-not(Get-Ini $ini 'M3K' 'Mode')){Set-Ini $ini 'M3K' 'Mode' '0'}

    $receipt=@(
        'GTA IV Scaling',
        "Version=$Version",
        "Installed=$(Get-Date -Format o)",
        "GPU=$($gpu.Name)",
        "NvidiaRtxAvailable=$(if($gpu.IsRtx){1}else{0})",
        "DefaultScalingTechnology=$tech",
        "NeuralRendering=$(if($gpu.Series-in@(20,30,40,50)){'installed-off-by-default'}else{'not-applicable'})",
        "Pre123Backup=$backup"
    )
    [IO.File]::WriteAllLines((Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'),$receipt,[Text.UTF8Encoding]::new($false))
    Write-Host ''
    if($gpu.Series-in@(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage}
    Write-Host 'GTA IV Scaling 1.2.6 installed / repaired successfully.' -ForegroundColor Green
}
function Remove-ScalingLeftovers([string]$Root){
    foreach($name in @(
        'GTAIV_SCALING_INSTALLED.txt',
        'DLAA_INSTALL_MANIFEST.txt',
        'DLAA_AIO_install.log',
        'DLSS_FULL_INSTALLED.txt',
        'DLSS_FULL_install.log',
        'DLSS_FULL_uninstall.log',
        'DLSS-Full-Control.bat',
        'Uninstall-DLSS-Full.bat',
        '_GTAIV_DLSS_Install-DLAA-Core.bat',
        '_GTAIV_DLSS_Install-DLSS-Full-Core.bat'
    )){
        Remove-Item -LiteralPath (Join-Path $Root $name) -Force -ErrorAction SilentlyContinue
    }
    foreach($pattern in @(
        '_GTAIV_SCALING_PRE*_BACKUP_*',
        '_DLAA_PREINSTALL_BACKUP_*',
        '_DLSS_FULL_PREINSTALL_BACKUP_*',
        '_DLSS_FULL_UNINSTALL_SAFETY_*',
        '_DLAA_UNINSTALL_SAFETY_*'
    )){
        Get-ChildItem -LiteralPath $Root -Directory -Filter $pattern -ErrorAction SilentlyContinue |
            ForEach-Object{Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue}
    }
    foreach($name in @('_DLSS_FULL_DLAA_BASELINE')){
        Remove-Item -LiteralPath (Join-Path $Root $name) -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Remove-FusionFix([string]$Root){
    $receipt=Join-Path $Root 'GTAIV-FUSIONFIX-LATEST.json'
    if(Test-Path -LiteralPath $receipt -PathType Leaf){
        $record=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
        if(-not $record.files){Fail 'FusionFix file manifest is missing; refusing broad, potentially destructive uninstall.'}
        $backup=[string]$record.backup
        $restored=0
        $removed=0
        $preserved=0
        foreach($item in $record.files){
            $rel=[string]$item.path
            if(-not $rel -or [IO.Path]::IsPathRooted($rel) -or
               $rel -match '(^|[\\/])\.\.([\\/]|$)' -or $rel -match '^[a-zA-Z]:'){
                Fail "Unsafe path in FusionFix manifest: $rel"
            }
            if($rel -match '(?i)(^|[\\/])GTAIV\.EFLC\.FusionFix\.(ini|cfg)$'){continue}
            $dst=Join-Path $Root $rel
            if(-not(Test-Path -LiteralPath $dst -PathType Leaf)){continue}
            $currentHash=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToUpperInvariant()
            if($currentHash -ne ([string]$item.sha256).ToUpperInvariant()){
                # Another mod or the user has changed this file since installation.
                $preserved++
                continue
            }
            if($item.had_existing){
                $original=Join-Path $backup $rel
                if(-not(Test-Path -LiteralPath $original -PathType Leaf)){
                    Fail "Backup is missing for $rel. Refusing to remove FusionFix without a safe rollback."
                }
                Copy-Item -LiteralPath $original -Destination $dst -Force
                $restored++
            }else{
                Remove-Item -LiteralPath $dst -Force
                $removed++
            }
        }
        Remove-Item -LiteralPath $receipt -Force
        Write-Host "FusionFix cleanup: removed=$removed restored=$restored user-modified-preserved=$preserved. User settings preserved."
        return
    }
    # Legacy 5.0.1 installations (from older Scaling installers) lack a version receipt.
    # Keep the legacy uninstall only for that earlier pinned package.
    Write-Host 'Removing legacy pinned FusionFix 5.0.1 files (no latest-release manifest detected)...' -ForegroundColor Cyan
    $zip=Resolve-FusionFixPackage
    Assert-SHA256 $zip '3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41' 'FusionFix legacy package'
    $out=Join-Path (Get-AutoTemp) 'fusionfix-remove'
    Expand-Archive -LiteralPath $zip -DestinationPath $out -Force
    $dinput=Get-ChildItem -LiteralPath $out -Recurse -File -Filter 'dinput8.dll'|Select-Object -First 1
    if(-not $dinput){Fail 'FusionFix legacy package did not contain dinput8.dll.'}
    $packageRoot=$dinput.Directory.FullName
    foreach($file in @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force)){
        $rel=$file.FullName.Substring($packageRoot.Length).TrimStart('\','/')
        if(-not $rel -or $rel -match '(?i)(^|[\\/])GTAIV\.EFLC\.FusionFix\.(ini|cfg)$'){continue}
        $dst=Join-Path $Root $rel
        if(Test-Path -LiteralPath $dst -PathType Leaf){Remove-Item -LiteralPath $dst -Force}
    }
}
function Remove-Scaling([string]$Root,[bool]$KeepFusionFix){
    $uninstall=Join-Path $PSScriptRoot 'Uninstall-DLAA.bat'
    Invoke-Bat $uninstall $Root -NonInteractive
    Remove-ScalingLeftovers $Root
    if(-not $KeepFusionFix){Remove-FusionFix $Root}
}

trap{
    $message=$_.Exception.Message
    Write-Host ''
    Write-Host ('GTA IV Scaling setup failed: '+$message) -ForegroundColor Red
    Write-Result $message
    if($script:Temp -and (Test-Path -LiteralPath $script:Temp)){Remove-Item $script:Temp -Recurse -Force -ErrorAction SilentlyContinue}
    exit 1
}

$Game=Normalize-GamePath $Game
if($Action-eq'INSTALL'){Install-Scaling $Game}
elseif($Action-eq'UPDATE_NR'){Invoke-NrUpdate $Game $NrPackage}
elseif($Action-eq'UPDATE_FUSIONFIX'){Invoke-LatestFusionFix $Game}
elseif($Action-eq'REMOVE_KEEP_FUSIONFIX'){Remove-Scaling $Game $true}
else{Remove-Scaling $Game $false}
Write-Result 'OK'
if($script:Temp -and (Test-Path -LiteralPath $script:Temp)){Remove-Item $script:Temp -Recurse -Force -ErrorAction SilentlyContinue}
exit 0
