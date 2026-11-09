@rem GTAIV-DLAA-DLSS5 clean baseline installer. Normal users should launch it through GTAIV-DLSS-Setup.exe.
@echo off
setlocal
set "DLAA_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLAA_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
$Self=$env:DLAA_SELF
$Game=if($env:GTAIV_SETUP_GAME){(Resolve-Path -LiteralPath $env:GTAIV_SETUP_GAME).Path}else{Split-Path -Parent $Self}
$Trex=Join-Path $Game '.trex'; $Temp=Join-Path $env:TEMP ("GTAIV_DLAA_AIO_"+$PID)
$ReshadeSetup=$env:GTAIV_SETUP_RESHADE; $LumenitePackage=$env:GTAIV_SETUP_LUMENITE
$ReShadeSetupHash='AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445'
$LumenitePackageHash='572FEFB20D466AFE50998E16996B4833BEC675264485C99FE768A2337636E756'
$ReleaseApi='https://api.github.com/repos/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/releases/tags/v1.2.10'
$RuntimeAsset='GTAIV-DLSS-Full-Runtime.zip'
$RuntimeZipHash='AC87DBADAD84124F24B02D328AA58B5AD354511AA322C6D2721F2FF4125B2DC3'
$RuntimeHashes=@{
 'bridge.conf'='161557ED3B3DEE86D9B9BEA3D3323924EE1F9F7FF47A139E3075B787B752EC8C';
 'd3d9.dll'='8F008B1465BAC3A6233207147B628F9AAFCAB81E441AF539EDF4F7AE0D40C74C';
 'd3d9vk_x64.dll'='46BA25955418C0C2A95CC1EEF53BD13D8FB71336D0040939F5EA862A94934CE7';
 'DLSS5_Feed.fx'='CDAC08A721B14B97187DD86C5B5BEAD157C9063D7EE859A0F131A8EE791695F1';
 'dlss5-feed.addon64'='01B212F6A7A37351E41E31BADD21C99B6428BF545AE9A0F8EA88BE6FB2510981';
 'DrawText.fxh'='3509C6C02C33A4390AE5410740CDD287B410618CBA2915A4733B148A5798A0FC';
 'dxvk.conf'='A317EDB736464EF90037B9F8A9267CDCB00905D485E7FE0E1E30F3C456F842EE';
 'M3K_Sharpen.fx'='20E2F9C918B2AAEC1B1C19CF732038506DC604B3455FAEEAD3147A11F0275429';
 'nvngx_dlss.dll'='3975567B8943C53ACCE397F2B72380092F84F162D00B0D2C7D08A1025C563983';
 'NvRemixBridge.exe'='A1DEFF50067CB7D3EC2A656E69B7D95E08201E1844493089DEA87ECA06F226C2';
 'ReShade.fxh'='BFA89183CFEB99968A58E751CD23AFA2F5FF56332B3CF7F08F23E39879BADC70';
 'ReShadeUI.fxh'='B95EEF44289C97FF027E5C70EC579F5FBB3C375037544C4F2913C4F33C7D5D53';
 'licenses\LICENSE'='1CE240E402901FB81EB82A60A6BAFD2FB913CD5746860B0A4EC52A5ACB49CED7';
 'licenses\LICENSE-MIT'='0796ABEB083FD473B341CEFB755837EAC78887458B0F86ACB2599A736D42A540';
 'licenses\LICENSE.txt'='3027F23CA5A46DD9CB8183FBD522983A86F64D7DAAC5982912BF9F214671F294';
 'licenses\ThirdPartyLicenses.txt'='51F50CD458859A644BDD59845B65536BAA214941A6885FCF0536F362FBDF69E6';
 'm3k\m3k-nvngx.dll'='581AEB29EAA06CAF737745513F26230CE4E01A0F05E0F32BAB91C452FEA88F6D';
}
$ReShadeInstalled=$false; $TranscriptStarted=$false; $Backup=$null
function Fail([string]$m){throw $m}
function Resolve-ProjectAssetUrl([string]$AssetName){$headers=@{'User-Agent'='GTAIV-DLSS-Setup'};$release=Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $ReleaseApi;$asset=@($release.assets|Where-Object{$_.name -eq $AssetName})|Select-Object -First 1;if(-not $asset -or -not $asset.browser_download_url){Fail "Project release asset was not found: $AssetName"};return [string]$asset.browser_download_url}
function Is-Admin{$id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object Security.Principal.WindowsPrincipal($id);return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function Download([string]$u,[string]$d){Write-Host "Downloading project runtime: $u" -ForegroundColor Cyan;$curl=Get-Command curl.exe -ErrorAction SilentlyContinue;if($curl){& curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $d $u;if($LASTEXITCODE -ne 0){Fail "Download failed: $u"}}else{Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $d};if(-not(Test-Path -LiteralPath $d)){Fail "Downloaded file is missing: $d"}}
function Assert-SHA256([string]$p,[string]$e){$a=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant();if($a -ne $e.ToUpperInvariant()){Fail "SHA256 mismatch for $p`nExpected: $e`nActual:   $a"}}
function Write-NoBom([string]$p,[string[]]$l){[IO.File]::WriteAllLines($p,$l,(New-Object Text.UTF8Encoding($false)))}
function Set-IniValue([string]$Path,[string]$Section,[string]$Key,[string]$Value){if(Test-Path -LiteralPath $Path){$arr=@(Get-Content -LiteralPath $Path)}else{$arr=@()};$lines=New-Object 'System.Collections.Generic.List[string]';foreach($x in $arr){[void]$lines.Add([string]$x)};$sec='['+$Section+']';$start=-1;for($i=0;$i -lt $lines.Count;$i++){if($lines[$i].Trim() -ieq $sec){$start=$i;break}};if($start -lt 0){if($lines.Count -gt 0 -and $lines[$lines.Count-1] -ne ''){[void]$lines.Add('')};[void]$lines.Add($sec);[void]$lines.Add("$Key=$Value")}else{$end=$lines.Count;for($i=$start+1;$i -lt $lines.Count;$i++){if($lines[$i] -match '^\s*\[.+\]\s*$'){$end=$i;break}};$found=$false;for($i=$start+1;$i -lt $end;$i++){if($lines[$i] -match ('^\s*'+[regex]::Escape($Key)+'\s*=')){$lines[$i]="$Key=$Value";$found=$true;break}};if(-not $found){$lines.Insert($start+1,"$Key=$Value")}};Write-NoBom $Path $lines.ToArray()}
function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value){$text=if(Test-Path -LiteralPath $Path){[IO.File]::ReadAllText($Path)}else{''};$pat='(?m)^\s*'+[regex]::Escape($Key)+'\s*=\s*.*$';$line="$Key = $Value";if($text -match $pat){$text=[regex]::Replace($text,$pat,$line)}else{if($text.Length -gt 0 -and -not $text.EndsWith("`n")){$text+="`r`n"};$text+=$line+"`r`n"};[IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($false)))}
function Merge-KeyValueDefaults([string]$Source,[string]$Target){
 if(-not(Test-Path -LiteralPath $Source -PathType Leaf)){Fail "Missing runtime defaults: $Source"}
 if(-not(Test-Path -LiteralPath $Target -PathType Leaf)){
  $parent=Split-Path -Parent $Target;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  Copy-Item -LiteralPath $Source -Destination $Target -Force;return
 }
 foreach($line in [IO.File]::ReadAllLines($Source)){
  if($line -match '^\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)$'){
   $key=$Matches[1];$value=$Matches[2];$current=[IO.File]::ReadAllText($Target)
   if(-not [regex]::IsMatch($current,'(?im)^\s*'+[regex]::Escape($key)+'\s*=')){Set-KeyEquals $Target $key $value}
  }
 }
}
function Copy-IfExists([string]$s,[string]$d){if(Test-Path -LiteralPath $s){$p=Split-Path -Parent $d;if($p -and -not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null};Copy-Item -LiteralPath $s -Destination $d -Force}}
function Cleanup{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}

function Write-SetupResult([string]$Message){
 if(-not $env:GTAIV_SETUP_RESULT_FILE){return}
 try{[IO.File]::WriteAllText($env:GTAIV_SETUP_RESULT_FILE,$Message,[Text.UTF8Encoding]::new($false))}catch{}
}
function Restore-GameBaseline([string]$BackupPath){
 if(-not $BackupPath -or -not(Test-Path -LiteralPath $BackupPath -PathType Container)){return}
 Write-Host "Restoring clean FusionFix baseline from $BackupPath" -ForegroundColor Yellow
 if(Test-Path -LiteralPath $Trex){Remove-Item -LiteralPath $Trex -Recurse -Force -ErrorAction SilentlyContinue}
 $hook=Join-Path $Game 'd3d9Hooked.dll';if(Test-Path -LiteralPath $hook){Remove-Item -LiteralPath $hook -Force -ErrorAction SilentlyContinue}
 foreach($n in @('d3d9.dll','vulkan.dll','dxvk.conf','commandline.txt')){
   $src=Join-Path $BackupPath $n;$dst=Join-Path $Game $n
   if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $dst -Force}
   elseif(Test-Path -LiteralPath $dst){Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue}
 }
 $bp=Join-Path $BackupPath 'plugins';$gp=Join-Path $Game 'plugins'
 if(Test-Path -LiteralPath $bp -PathType Container){
   New-Item -ItemType Directory -Path $gp -Force|Out-Null
   Get-ChildItem -LiteralPath $bp -File -ErrorAction SilentlyContinue|ForEach-Object{Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $gp $_.Name) -Force}
 }
}
function Recover-PartialPreviousAttempt{
 $partial=(Test-Path -LiteralPath $Trex -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Game 'd3d9Hooked.dll') -PathType Leaf)
 $complete=(Test-Path -LiteralPath (Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt') -PathType Leaf)
 if(-not $partial -or $complete){return}
 $backup=Get-ChildItem -LiteralPath $Game -Directory -Filter '_DLAA_PREINSTALL_BACKUP_*' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
 if(-not $backup){Fail 'A partial previous DLAA install was detected, but no _DLAA_PREINSTALL_BACKUP_* folder exists to restore it safely.'}
 Write-Host 'Partial previous DLAA attempt detected. Rolling it back automatically...' -ForegroundColor Yellow
 Restore-GameBaseline $backup.FullName
}

if(-not(Is-Admin)){Write-Host 'Administrator permission is required for the ReShade Vulkan layer.' -ForegroundColor Yellow;$p=Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru;exit $p.ExitCode}
$Log=Join-Path $Game 'DLAA_AIO_install.log'
try{
 Start-Transcript -LiteralPath $Log -Force|Out-Null;$TranscriptStarted=$true
 if(-not(Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))){Fail 'GTAIV.exe was not found.'};if(-not(Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))){Fail 'FusionFix is not detected.'}
 Recover-PartialPreviousAttempt
 if(Test-Path -LiteralPath $Trex){Fail '.trex already exists after recovery; baseline is not clean.'};if(Test-Path -LiteralPath (Join-Path $Game 'd3d9Hooked.dll')){Fail 'd3d9Hooked.dll already exists after recovery; baseline is not clean.'}
 if(-not $ReshadeSetup -or -not(Test-Path -LiteralPath $ReshadeSetup)){Fail 'Official ReShade installer was not supplied.'};Assert-SHA256 $ReshadeSetup $ReShadeSetupHash
 if(-not $LumenitePackage -or -not(Test-Path -LiteralPath $LumenitePackage)){Fail 'LumeniteFX ZIP was not supplied.'};Assert-SHA256 $LumenitePackage $LumenitePackageHash
 $ffCfg=$null;$cfgName='GTAIV.EFLC.FusionFix.cfg'
 foreach($candidate in @(
   (Join-Path $Game "plugins\$cfgName"),
   (Join-Path $Game $cfgName),
   (Join-Path $env:LOCALAPPDATA "Rockstar Games\GTA IV\$cfgName"),
   (Join-Path $env:LOCALAPPDATA "GTAIV.EFLC.FusionFix\$cfgName"),
   (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "GTAIV.EFLC.FusionFix\$cfgName")
 )){if(Test-Path -LiteralPath $candidate -PathType Leaf){$ffCfg=$candidate;break}}
 if(-not $ffCfg){
   $pluginDir=Join-Path $Game 'plugins'
   if(Test-Path -LiteralPath $pluginDir -PathType Container){
     $o=Get-ChildItem -LiteralPath $pluginDir -Filter '*FusionFix*.cfg' -File -ErrorAction SilentlyContinue|Select-Object -First 1
     if($o){$ffCfg=$o.FullName}
   }
 }
 if(-not $ffCfg){Fail 'FusionFix CFG not found in any supported first-run location.'}
 $stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$Backup=Join-Path $Game ("_DLAA_PREINSTALL_BACKUP_"+$stamp);New-Item -ItemType Directory -Path (Join-Path $Backup 'plugins') -Force|Out-Null
 foreach($n in @('d3d9.dll','vulkan.dll','dxvk.conf','commandline.txt')){Copy-IfExists (Join-Path $Game $n) (Join-Path $Backup $n)};Copy-IfExists $ffCfg (Join-Path $Backup ('plugins\'+[IO.Path]::GetFileName($ffCfg)));$ffIni=Join-Path (Split-Path -Parent $ffCfg) 'GTAIV.EFLC.FusionFix.ini';Copy-IfExists $ffIni (Join-Path $Backup 'plugins\GTAIV.EFLC.FusionFix.ini')
 Cleanup;New-Item -ItemType Directory -Path $Temp -Force|Out-Null;$runtimeZip=Join-Path $Temp 'runtime.zip';$runtime=Join-Path $Temp 'runtime';$lum=Join-Path $Temp 'lumenite'
 if($env:GTAIV_SETUP_PROJECT_RUNTIME -and (Test-Path -LiteralPath $env:GTAIV_SETUP_PROJECT_RUNTIME -PathType Leaf)){Write-Host 'Using local project runtime beside setup EXE.' -ForegroundColor DarkGray;Copy-Item -LiteralPath $env:GTAIV_SETUP_PROJECT_RUNTIME -Destination $runtimeZip -Force}else{$runtimeUrl=Resolve-ProjectAssetUrl $RuntimeAsset;Download $runtimeUrl $runtimeZip};Assert-SHA256 $runtimeZip $RuntimeZipHash;Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtime -Force
 foreach($rel in $RuntimeHashes.Keys){$p=Join-Path $runtime $rel;if(-not(Test-Path -LiteralPath $p)){Fail "Project runtime is missing $rel. Rebuild GTAIV-DLSS-Full-Runtime.zip with the cleaned runtime workflow."};Assert-SHA256 $p $RuntimeHashes[$rel]}
 Expand-Archive -LiteralPath $LumenitePackage -DestinationPath $lum -Force
 Set-IniValue $ffCfg 'MAIN' 'GraphicsAPI' '0';Set-IniValue $ffCfg 'MAIN' 'Windowed' '1';Set-IniValue $ffCfg 'MAIN' 'BorderlessWindowed' '1';Set-IniValue $ffCfg 'FRAMELIMIT' 'FpsLimitPreset' '0';Set-IniValue $ffCfg 'MISC' 'Antialiasing' '5'
 $cmdPath=Join-Path $Game 'commandline.txt';$cmd=if(Test-Path -LiteralPath $cmdPath){[IO.File]::ReadAllText($cmdPath)}else{''};if($cmd -notmatch '(?i)(^|\s)-windowed(\s|$)'){if($cmd.Trim().Length -gt 0){$cmd=$cmd.TrimEnd()+"`r`n"};$cmd+="-windowed`r`n";[IO.File]::WriteAllText($cmdPath,$cmd,(New-Object Text.UTF8Encoding($false)))}
 $rootD3D9=Join-Path $Game 'd3d9.dll';if(Test-Path -LiteralPath $rootD3D9){Move-Item -LiteralPath $rootD3D9 -Destination (Join-Path $Game 'd3d9Hooked.dll') -Force};Copy-Item -LiteralPath (Join-Path $runtime 'd3d9.dll') -Destination $rootD3D9 -Force
 New-Item -ItemType Directory -Path $Trex -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $runtime 'NvRemixBridge.exe') -Destination (Join-Path $Trex 'NvRemixBridge.exe') -Force;Copy-Item -LiteralPath (Join-Path $runtime 'd3d9vk_x64.dll') -Destination (Join-Path $Trex 'd3d9vk_x64.dll') -Force;Merge-KeyValueDefaults (Join-Path $runtime 'bridge.conf') (Join-Path $Trex 'bridge.conf');Merge-KeyValueDefaults (Join-Path $runtime 'dxvk.conf') (Join-Path $Game 'dxvk.conf');Set-KeyEquals (Join-Path $Trex 'bridge.conf') 'clientFrameCap' '0'
 $rsTarget=Join-Path $Trex 'NvRemixBridge.exe';$rs=Start-Process -FilePath $ReshadeSetup -ArgumentList @("`"$rsTarget`"",'--api','vulkan','--headless') -Wait -PassThru;if($rs.ExitCode -ne 0){Fail "Official ReShade setup failed: $($rs.ExitCode)"};$ReShadeInstalled=$true;$rsIni=Join-Path $Trex 'ReShade.ini';if(-not(Test-Path -LiteralPath $rsIni)){Fail 'ReShade.ini was not created.'}
 $shaderDir=Join-Path $Trex 'reshade-shaders\Shaders';$texDir=Join-Path $Trex 'reshade-shaders\Textures';New-Item -ItemType Directory -Path $shaderDir -Force|Out-Null;New-Item -ItemType Directory -Path $texDir -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $runtime 'dlss5-feed.addon64') -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force;Copy-Item -LiteralPath (Join-Path $runtime 'DLSS5_Feed.fx') -Destination (Join-Path $shaderDir 'DLSS5_Feed.fx') -Force;Copy-Item -LiteralPath (Join-Path $runtime 'nvngx_dlss.dll') -Destination (Join-Path $Trex 'nvngx_dlss.dll') -Force
 foreach($h in @('ReShade.fxh','ReShadeUI.fxh','DrawText.fxh')){Copy-Item -LiteralPath (Join-Path $runtime $h) -Destination (Join-Path $shaderDir $h) -Force}
 $lumKernel=Get-ChildItem -LiteralPath $lum -Filter 'lumenite_Kernel.fx' -File -Recurse|Select-Object -First 1;if(-not $lumKernel){Fail 'Lumenite Kernel was not found in the selected ZIP.'};Copy-Item -Path (Join-Path $lumKernel.Directory.FullName '*') -Destination $shaderDir -Recurse -Force;$lumBlue=Get-ChildItem -LiteralPath $lum -Filter 'lumenite_bluenoise256.png' -File -Recurse|Select-Object -First 1;if($lumBlue){Copy-Item -LiteralPath $lumBlue.FullName -Destination (Join-Path $texDir 'lumenite_bluenoise256.png') -Force}
 Set-IniValue $rsIni 'GENERAL' 'EffectSearchPaths' '.\reshade-shaders\Shaders';Set-IniValue $rsIni 'GENERAL' 'TextureSearchPaths' '.\reshade-shaders\Textures';Set-IniValue $rsIni 'GENERAL' 'PresetPath' '.\ReShadePreset.ini';Set-IniValue $rsIni 'ADDON' 'AddonPath' '.\';Set-IniValue $rsIni 'INPUT' 'KeyOverlay' '46,0,0,0'
 Write-NoBom (Join-Path $Trex 'ReShadePreset.ini') @('Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx','TechniqueSorting=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx,DLSS5_Feed_Debug@DLSS5_Feed.fx','','[DLSS5_Feed.fx]','PreprocessorDefinitions=DLSS5_MV_PROVIDER=3');Write-NoBom (Join-Path $Trex 'dlss5-feed.cfg') @('enabled=1','mode=2','work_resolution=100')
 foreach($n in @('nvngx_dlssnr.dll','renodx-dlss5.addon64','deep-fried-chicken.addon64','deep-fried-chicken-nvngx.dll','OptiScaler.dll','OptiScaler.ini')){$p=Join-Path $Trex $n;if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}
 $manifest=@"
GTA IV DLAA clean installation
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
ReShade: official 6.8.0 Full Add-On Support selected through setup
LumeniteFX: pinned GitHub archive downloaded/verified by setup
DLSS5-Feeder: project runtime
nvngx_dlss.dll: official NVIDIA 310.9.1 packaged in project runtime
DLSS5 Neural Rendering: NOT INSTALLED
Pre-install backup:
$Backup
"@;[IO.File]::WriteAllText((Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt'),$manifest,(New-Object Text.UTF8Encoding($false)))
 Write-Host '';Write-Host 'SUCCESS: GTA IV DLAA STACK INSTALLED' -ForegroundColor Green
 if($TranscriptStarted){Stop-Transcript|Out-Null;$TranscriptStarted=$false};exit 0
}catch{$err=$_.Exception.Message;Write-Host '';Write-Host 'INSTALL FAILED:' -ForegroundColor Red;Write-Host $err -ForegroundColor Red
 Write-SetupResult $err
 try{if($ReShadeInstalled -and (Test-Path -LiteralPath $ReshadeSetup) -and (Test-Path -LiteralPath (Join-Path $Trex 'NvRemixBridge.exe'))){$target=Join-Path $Trex 'NvRemixBridge.exe';Start-Process -FilePath $ReshadeSetup -ArgumentList @("`"$target`"",'--api','vulkan','--headless','--state','uninstall') -Wait|Out-Null}}catch{}
 try{if($Backup){Restore-GameBaseline $Backup}}catch{Write-Host ('Rollback warning: '+$_.Exception.Message) -ForegroundColor Yellow}
 if($TranscriptStarted){try{Stop-Transcript|Out-Null}catch{};$TranscriptStarted=$false};Read-Host 'Press Enter to close';exit 1
}finally{Cleanup}
