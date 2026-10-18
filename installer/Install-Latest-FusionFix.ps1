[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Game,
    [switch]$CheckOnly,
    [switch]$Force,
    [string]$ResultFile='',
    # Test inputs are used by the isolated CI fixture, never by the GUI launcher.
    [string]$TestReleaseMetadataPath='',
    [string]$LocalArchive=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$script:TempPath=$null
$Repo='ThirteenAG/GTAIV.EFLC.FusionFix'
$Asset='GTAIV.EFLC.FusionFix.zip'
$ReceiptName='GTAIV-FUSIONFIX-LATEST.json'
function Say([string]$Message){Write-Host $Message}
function WriteResult([string]$Message){
    if($ResultFile){try{[IO.File]::WriteAllText($ResultFile,$Message,[Text.UTF8Encoding]::new($false))}catch{}}
}
function GameRoot([string]$Candidate){
    $p=$Candidate.Trim().Trim('"')
    if(-not $p){throw 'Please select your GTA IV game folder.'}
    if((Test-Path -LiteralPath $p -PathType Leaf)-and([IO.Path]::GetFileName($p)-ieq'GTAIV.exe')){$p=Split-Path -Parent $p}
    if(Test-Path -LiteralPath (Join-Path $p 'GTAIV.exe') -PathType Leaf){return (Resolve-Path -LiteralPath $p).Path}
    $inside=Join-Path $p 'GTAIV'
    if(Test-Path -LiteralPath (Join-Path $inside 'GTAIV.exe') -PathType Leaf){return (Resolve-Path -LiteralPath $inside).Path}
    throw 'GTAIV.exe was not found. Choose the game folder, not the launcher folder.'
}
function LatestRelease{
    if($TestReleaseMetadataPath){
        if(-not(Test-Path -LiteralPath $TestReleaseMetadataPath -PathType Leaf)){throw 'Test release metadata missing.'}
        return ([IO.File]::ReadAllText($TestReleaseMetadataPath)|ConvertFrom-Json)
    }
    Say 'Checking latest stable FusionFix on official GitHub...'
    $h=@{'User-Agent'='GTAIV-FusionFix-Latest-Installer';'Accept'='application/vnd.github+json'}
    return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing -Headers $h -TimeoutSec 45
}
function GetArchiveInfo($Release){
    if($Release.draft -or $Release.prerelease){throw 'GitHub returned a draft/prerelease, not a stable FusionFix release.'}
    $tag=[string]$Release.tag_name
    if($tag -notmatch '^v[0-9]+\.[0-9]+(?:\.[0-9]+){0,2}$'){throw "Unexpected FusionFix version: $tag"}
    $assets=@($Release.assets|Where-Object {$_.name -ceq $Asset})
    if($assets.Count -ne 1){throw "Stable $tag does not have the expected official FusionFix ZIP asset."}
    $asset=$assets[0]
    $digest=[string]$asset.digest
    if($digest -notmatch '^sha256:([0-9a-fA-F]{64})$'){
        throw "FusionFix $tag has no published SHA256 digest. Refusing an unverified install."
    }
    $hash=$Matches[1].ToUpperInvariant()
    $url=[string]$asset.browser_download_url
    $expectedUrl=('https://github.com/{0}/releases/download/{1}/{2}' -f $Repo,$tag,$Asset)
    if($url -cne $expectedUrl){throw "FusionFix ZIP URL does not match the official GitHub release. Got: [$url] Expected: [$expectedUrl]"}
    return [pscustomobject]@{Version=$tag;Url=$url;Hash=$hash}
}
function AssertArchive([string]$ZipPath,[string]$Sha){
    if(-not(Test-Path -LiteralPath $ZipPath -PathType Leaf)){throw 'FusionFix ZIP download is missing.'}
    $actual=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual-ne$Sha){throw "FusionFix ZIP SHA256 mismatch. Expected $Sha, got $actual. Nothing was installed."}
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($ZipPath)
    try{
        foreach($entry in $archive.Entries){
            $name=$entry.FullName.Replace('\','/')
            if($name.StartsWith('/') -or $name -match '^[a-zA-Z]:' -or
                $name -match '(^|/)\.\.(/|$)' -or $name -match '(^|/)\.(/|$)' -or
                $name.Contains([char]0)){
                throw "Unsafe FusionFix ZIP path: $name"
            }
        }
    }finally{$archive.Dispose()}
}
function PreserveUserSettings([string]$Relative){
    $name=$Relative.Replace('/','\')
    return $name -match '(?i)(^|\\)GTAIV\.EFLC\.FusionFix\.(cfg|ini)$'
}
function InstallLatest{
    $root=GameRoot $Game
    foreach($process in @('GTAIV','NvRemixBridge')){
        if(Get-Process -Name $process -ErrorAction SilentlyContinue){throw "Close $process.exe before installing FusionFix."}
    }
    $release=LatestRelease
    $info=GetArchiveInfo $release
    Say "Latest stable FusionFix: $($info.Version)"
    Say "Official source: $($info.Url)"
    if($CheckOnly){WriteResult "Latest: $($info.Version)";return}
    $receipt=Join-Path $root $ReceiptName
    if(-not $Force -and (Test-Path -LiteralPath $receipt -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $root 'dinput8.dll') -PathType Leaf)){
        try{
            $installed=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
            if($installed.version -ceq $info.Version -and $installed.sha256 -ceq $info.Hash){
                Say "Already installed: $($info.Version) (use -Force to reinstall)."
                WriteResult "Already installed: $($info.Version)"
                return
            }
        }catch{}
    }
    $script:TempPath=Join-Path $env:TEMP ('GTAIV_FUSIONFIX_'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempPath -Force|Out-Null
    $zip=Join-Path $script:TempPath $Asset
    if($LocalArchive){
        if(-not(Test-Path -LiteralPath $LocalArchive -PathType Leaf)){throw 'Local test archive does not exist.'}
        Copy-Item -LiteralPath $LocalArchive -Destination $zip -Force
    }else{
        Say 'Downloading verified FusionFix release (~200 MB)...'
        $headers=@{'User-Agent'='GTAIV-FusionFix-Latest-Installer'}
        Invoke-WebRequest -UseBasicParsing -Uri $info.Url -Headers $headers -OutFile $zip -TimeoutSec 300
    }
    Say 'Verifying official SHA256 and archive paths...'
    AssertArchive $zip $info.Hash
    $stage=Join-Path $script:TempPath 'stage'
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    $loaders=@(Get-ChildItem -LiteralPath $stage -File -Recurse -Filter 'dinput8.dll')
    if($loaders.Count-ne1){throw 'FusionFix archive must contain exactly one dinput8.dll.'}
    $packageRoot=$loaders[0].Directory.FullName
    $files=@(Get-ChildItem -LiteralPath $packageRoot -File -Recurse -Force)
    if($files.Count-lt2){throw 'FusionFix package appears incomplete.'}
    if(@(Get-ChildItem -LiteralPath $packageRoot -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue).Count){
        throw 'FusionFix archive contains unexpected filesystem links.'
    }
    $prefix=$packageRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $items=New-Object 'System.Collections.Generic.List[object]'
    $overwrite=0
    foreach($file in $files){
        $rel=$file.FullName.Substring($prefix.Length)
        if($rel -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($rel)){throw "Unsafe extracted path: $rel"}
        $dst=Join-Path $root $rel
        # User-modified FusionFix configuration survives the upgrade.
        if((PreserveUserSettings $rel) -and (Test-Path -LiteralPath $dst -PathType Leaf)){continue}
        if(Test-Path -LiteralPath $dst -PathType Container){throw "Cannot replace existing directory: $dst"}
        if(Test-Path -LiteralPath $dst -PathType Leaf){$overwrite++}
        $items.Add([pscustomobject]@{Source=$file.FullName;Relative=$rel;Target=$dst})
    }
    if($items.Count-lt2){throw 'FusionFix installation contains too few files.'}
    $backup=Join-Path $root ('_GTAIV_FUSIONFIX_BACKUP_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    $alreadyPresent=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    Say "Installing $($info.Version): $($items.Count) files, $overwrite existing files backed up."
    # Complete every backup BEFORE changing any game files.
    foreach($item in $items){
        if(Test-Path -LiteralPath $item.Target -PathType Leaf){
            $old=Join-Path $backup $item.Relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $old) -Force|Out-Null
            Copy-Item -LiteralPath $item.Target -Destination $old -Force
            [void]$alreadyPresent.Add($item.Relative)
        }
    }
    if(Test-Path -LiteralPath $receipt -PathType Leaf){Copy-Item -LiteralPath $receipt -Destination (Join-Path $backup $ReceiptName) -Force}
    $copied=New-Object 'System.Collections.Generic.List[object]'
    try{
        foreach($item in $items){
            New-Item -ItemType Directory -Path (Split-Path -Parent $item.Target) -Force|Out-Null
            Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
            $copied.Add($item)
        }
        if(-not(Test-Path -LiteralPath (Join-Path $root 'dinput8.dll') -PathType Leaf)){throw 'FusionFix dinput8.dll missing after installation.'}
        $record=[ordered]@{version=$info.Version;sha256=$info.Hash;source=$info.Url;installed_utc=[DateTime]::UtcNow.ToString('o');backup=$backup}
        [IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    }catch{
        Say 'Installation failed. Restoring the original files from backup...'
        foreach($item in $copied){
            try{
                if($alreadyPresent.Contains($item.Relative)){
                    Copy-Item -LiteralPath (Join-Path $backup $item.Relative) -Destination $item.Target -Force
                }else{
                    Remove-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
                }
            }catch{Write-Warning "Could not restore $($item.Relative): $_"}
        }
        throw
    }
    Say "FusionFix $($info.Version) installed successfully." 
    Say "Previous files backup: $backup"
    Say 'No DLSS, DXVK, ReShade or weapon mods were installed by this action.'
    WriteResult "Installed FusionFix $($info.Version)"
}
try{InstallLatest}
catch{
    $message=$_.Exception.Message
    Write-Host ("FusionFix setup failed: "+$message) -ForegroundColor Red
    WriteResult "FusionFix setup failed: $message"
    exit 1
}
finally{
    if($script:TempPath -and (Test-Path -LiteralPath $script:TempPath)){
        Remove-Item -LiteralPath $script:TempPath -Force -Recurse -ErrorAction SilentlyContinue
    }
}
exit 0
