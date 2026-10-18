[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Game,
      [string]$LocalPackage='',
      [string]$ResultFile='',
      [string]$CatalogUrl='https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/main/manifests/nr-versions.json')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$script:Temp=$null
function Fail([string]$m){throw $m}
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant()}
function GpuSeries{
    foreach($gpu in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)){
        if($gpu.Name -match '(?i)NVIDIA.*RTX\s*(20|30|40|50)\d{2}'){return [int]$Matches[1]}
    }
    Fail 'No supported RTX 20/30/40/50 GPU detected.'
}
function SourceUrl([string]$url){
    if($url -notmatch '^https://www\.mediafire\.com/file/'){return $url}
    $page=(Invoke-WebRequest -Uri $url -UseBasicParsing).Content
    $tag=[regex]::Match($page,'(?is)<a\b(?=[^>]*\bid\s*=\s*["'']downloadButton["''])[^>]*>')
    if(-not $tag.Success){Fail 'MediaFire direct link unavailable; choose a local DLL/archive instead.'}
    $href=[regex]::Match($tag.Value,'(?is)\bhref\s*=\s*["'']([^"'']+)["'']')
    if(-not $href.Success){Fail 'MediaFire download link unavailable.'}
    return [Net.WebUtility]::HtmlDecode($href.Groups[1].Value)
}
function Unpack([string]$archive,[string]$format,[string]$out){
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    if($format -eq 'zip'){Expand-Archive -LiteralPath $archive -DestinationPath $out -Force}
    elseif($format -eq 'rar'){
        $done=$false
        $tar=Get-Command tar.exe -ErrorAction SilentlyContinue
        if($tar){& $tar.Source -xf $archive -C $out; $done=($LASTEXITCODE -eq 0)}
        if(-not $done){
            $candidates=@('7z.exe',(Join-Path $env:ProgramFiles '7-Zip\7z.exe'))
            foreach($c in $candidates){
                $cmd=Get-Command $c -ErrorAction SilentlyContinue
                if($cmd){& $cmd.Source x "-o$out" -y $archive | Out-Null;$done=($LASTEXITCODE -eq 0);if($done){break}}
            }
        }
        if(-not $done){Fail 'RAR extraction unavailable. Install 7-Zip, or select the extracted nvngx_dlssnr.dll.'}
    }else{Fail "Unsupported archive format: $format"}
    $dlls=@(Get-ChildItem -LiteralPath $out -File -Recurse -Filter nvngx_dlssnr.dll)
    if($dlls.Count-ne1){Fail "Expected exactly one NR DLL; got $($dlls.Count)."}
    return $dlls[0].FullName
}
function Update{
    $root=$Game.Trim().Trim('"')
    if(-not(Test-Path -LiteralPath (Join-Path $root 'GTAIV.exe'))){
        $inner=Join-Path $root 'GTAIV'
        if(Test-Path -LiteralPath (Join-Path $inner 'GTAIV.exe')){$root=$inner}
        else{Fail 'Select the folder containing GTAIV.exe.'}
    }
    if(Get-Process GTAIV -ErrorAction SilentlyContinue){Fail 'Close GTAIV.exe first.'}
    if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe first.'}
    $target=Join-Path $root '.trex\m3k\nvngx_dlssnr.dll'
    if(-not(Test-Path -LiteralPath (Split-Path -Parent $target))){Fail 'GTA IV Scaling must already be installed.'}
    $series=GpuSeries
    Write-Host "Detected RTX $series" -ForegroundColor Cyan
    $catalog=Invoke-RestMethod -Uri $CatalogUrl -ErrorAction Stop
    if($catalog.schema-ne1){Fail 'Unknown NR catalog schema.'}
    $entry=$catalog.targets.PSObject.Properties["rtx$series"].Value
    if(-not $entry){Fail "No NR build approved for RTX $series."}
    $expected=([string]$entry.sha256).ToUpperInvariant()
    if($expected -notmatch '^[A-F0-9]{64}$'){Fail 'Invalid approved SHA256.'}
    # Avoid downloading a package that is already installed and verified.
    # A user-selected local package is always validated before deciding to keep it.
    if(-not $LocalPackage -and (Test-Path -LiteralPath $target -PathType Leaf) -and (Hash $target)-eq$expected){
        Write-Host "Already up to date: $($entry.label); no NR package downloaded." -ForegroundColor Green
        return
    }
    $script:Temp=Join-Path $env:TEMP ('GTAIV_NR_'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null
    if($LocalPackage){
        if(-not(Test-Path -LiteralPath $LocalPackage -PathType Leaf)){Fail 'Local DLL/archive not found.'}
        $file=(Resolve-Path -LiteralPath $LocalPackage).Path
        $format=[IO.Path]::GetExtension($file).TrimStart('.').ToLowerInvariant()
    }else{
        $format=[string]$entry.archive
        $file=Join-Path $script:Temp ("nr."+ $format)
        $url=SourceUrl ([string]$entry.page_url)
        if($url -notmatch '^https://'){Fail 'Refusing non-HTTPS download URL.'}
        Write-Host "Fetching $($entry.label)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $file -ErrorAction Stop
    }
    $candidate=if($format-eq'dll'){$file}else{Unpack $file $format (Join-Path $script:Temp 'unpacked')}
    if((Hash $candidate)-ne$expected){Fail "New NR DLL fails SHA256 validation (expected $expected). Nothing was replaced."}
    if($entry.signed_original){
        $sig=Get-AuthenticodeSignature -LiteralPath $candidate
        if($sig.Status-ne'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA'){
            Fail 'Original RTX 50 DLL must have a valid NVIDIA signature.'
        }
    }
    if((Test-Path -LiteralPath $target) -and (Hash $target)-eq$expected){
        Write-Host "Already up to date: $($entry.label)" -ForegroundColor Green
        return
    }
    $backup=Join-Path (Split-Path -Parent $target) ('_nr_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $had=Test-Path -LiteralPath $target -PathType Leaf
    if($had){Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'nvngx_dlssnr.dll') -Force}
    try{
        Copy-Item -LiteralPath $candidate -Destination $target -Force
        if((Hash $target)-ne$expected){Fail 'Post-install SHA256 verification failed.'}
    }catch{
        if($had){Copy-Item -LiteralPath (Join-Path $backup 'nvngx_dlssnr.dll') -Destination $target -Force}
        else{Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue}
        throw
    }
    $receipt=Join-Path (Split-Path -Parent $target) 'nr-installed.json'
    $data=@{version=$entry.version;variant=if($entry.signed_original){'NVIDIA original'}else{'ShortFuse compat'};sha256=$expected;gpu_series=$series;backup=$backup}
    [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Write-Host "Installed $($entry.label). Old NR DLL backed up at: $backup" -ForegroundColor Green
}
try{Update}
catch{
    Write-Host ("NR update failed: "+$_.Exception.Message) -ForegroundColor Red
    if($ResultFile){[IO.File]::WriteAllText($ResultFile,$_.Exception.Message,[Text.UTF8Encoding]::new($false))}
    exit 1
}
finally{if($script:Temp -and (Test-Path -LiteralPath $script:Temp)){Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue}}
if($ResultFile){[IO.File]::WriteAllText($ResultFile,'OK',[Text.UTF8Encoding]::new($false))}
exit 0
