@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "BB_SELF=%~f0"
set "PATCHED=%~dp0ReShade64-bbridge.dll"
set "RESHADESYS=C:\ProgramData\ReShade\ReShade64.dll"
set "BACKUP=C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input"
set "BB_PATCHED=%PATCHED%"
set "BB_RESHADESYS=%RESHADESYS%"

rem Ask for the game first, while this window is still non-elevated.
rem This also lets drag-and-drop from Explorer work normally.
set "GAME=%~1"
if not defined GAME (
  echo ============================================================
  echo ReShade b-bridge input patch installer
  echo ============================================================
  echo.
  echo Please enter the GTA IV game folder that contains GTAIV.exe.
  echo You can COPY/PASTE the path, or DRAG THE GTAIV FOLDER into this window.
  echo.
  echo Example:
  echo   B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV
  echo.
  set /p "GAME=Game folder: "
)

if not defined GAME (
  echo.
  echo ERROR: No game folder was entered.
  pause
  exit /b 1
)

set "GAME=%GAME:"=%"
for %%I in ("%GAME%") do if /I "%%~nxI"=="GTAIV.exe" set "GAME=%%~dpI"
if not exist "%GAME%\GTAIV.exe" if exist "%GAME%\GTAIV\GTAIV.exe" set "GAME=%GAME%\GTAIV"

if not exist "%GAME%\GTAIV.exe" (
  echo.
  echo ERROR: GTAIV.exe was not found there.
  echo Make sure you entered the folder that actually contains GTAIV.exe.
  pause
  exit /b 1
)

if not exist "%PATCHED%" (
  echo.
  echo ERROR: ReShade64-bbridge.dll not found.
  echo Double-click BUILD.bat first and wait for BUILD SUCCESS - PATCH MARKER VERIFIED.
  pause
  exit /b 1
)

rem Refuse to install a stale/stock ReShade DLL that merely has the expected filename.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:BB_PATCHED;$s=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p));if($s.IndexOf('b-bridge input relay') -lt 0){Write-Host 'ERROR: ReShade64-bbridge.dll is not actually patched. Re-run the UPDATED BUILD.bat.' -ForegroundColor Red;exit 91}" || (
  echo.
  echo INSTALL STOPPED BEFORE MAKING CHANGES.
  pause
  exit /b 1
)

rem Request Administrator permission automatically and pass the chosen game folder on.
net session >nul 2>nul
if errorlevel 1 (
  set "BB_GAME=%GAME%"
  echo.
  echo Windows will now ask for Administrator permission.
  echo Click Yes to continue installing the patched ReShade Vulkan DLL.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$arg=[char]34+$env:BB_GAME+[char]34; Start-Process -FilePath $env:BB_SELF -ArgumentList $arg -Verb RunAs" || (
    echo ERROR: Could not request Administrator permission.
    pause
    exit /b 1
  )
  exit /b 0
)

set "TREX=%GAME%\.trex"
set "BB_TREX=%TREX%"
set "POC=%TREX%\bridge-input.addon64"
set "POCDISABLED=%TREX%\bridge-input.addon64.poc-disabled"

echo.
echo Using game folder:
echo   "%GAME%"
echo.

if not exist "%TREX%\NvRemixBridge.exe" (
  echo ERROR: b-bridge server not found:
  echo   "%TREX%\NvRemixBridge.exe"
  echo Complete Steps 1 and 2 of the main README first.
  pause
  exit /b 1
)
if not exist "%RESHADESYS%" (
  echo ERROR: Existing global ReShade Vulkan DLL not found:
  echo   "%RESHADESYS%"
  echo Install the ReShade Vulkan layer through Install-DLAA.bat first.
  pause
  exit /b 1
)

for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is running. Fully close GTA IV first.
    pause
    exit /b 1
  )
)

if not exist "%BACKUP%" (
  echo Backing up current ReShade64.dll...
  copy /y "%RESHADESYS%" "%BACKUP%" >nul || (
    echo ERROR: Could not create backup.
    pause
    exit /b 1
  )
) else (
  echo Existing backup preserved:
  echo   "%BACKUP%"
)

if exist "%POC%" (
  echo Disabling old bridge-input POC add-on...
  if exist "%POCDISABLED%" del /q "%POCDISABLED%"
  ren "%POC%" "bridge-input.addon64.poc-disabled" || (
    echo ERROR: Could not disable old POC add-on.
    pause
    exit /b 1
  )
)

echo Installing patched global ReShade Vulkan DLL...
copy /y "%PATCHED%" "%RESHADESYS%" >nul || (
  echo ERROR: Could not replace "%RESHADESYS%"
  echo Another Vulkan/ReShade application may still have it loaded.
  pause
  exit /b 1
)

rem Verify the global file is byte-for-byte the same DLL we just built.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$a=(Get-FileHash -Algorithm SHA256 -LiteralPath $env:BB_PATCHED).Hash;$b=(Get-FileHash -Algorithm SHA256 -LiteralPath $env:BB_RESHADESYS).Hash;if($a -ne $b){Write-Host 'ERROR: installed ReShade64.dll does not match ReShade64-bbridge.dll.' -ForegroundColor Red;Write-Host ('Built:     '+$a);Write-Host ('Installed: '+$b);exit 92};$s=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($env:BB_RESHADESYS));if($s.IndexOf('b-bridge input relay') -lt 0){Write-Host 'ERROR: installed DLL is missing the patch marker.' -ForegroundColor Red;exit 93};Write-Host ('Verified installed patched DLL SHA256: '+$a) -ForegroundColor Green" || (
  echo.
  echo ERROR: Patched ReShade verification failed.
  echo The installer will NOT claim Step 3 succeeded.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Join-Path $env:BB_TREX 'bridge.conf'; if(!(Test-Path -LiteralPath $p)){throw 'bridge.conf not found'}; $t=[IO.File]::ReadAllText($p); foreach($kv in @(@('client.DirectInput.forward.mousePolicy','3'),@('client.DirectInput.forward.keyboardPolicy','3'))){$k=$kv[0];$v=$kv[1];$pat='(?m)^\s*'+[regex]::Escape($k)+'\s*=.*$';$line=$k+' = '+$v;if($t -match $pat){$t=[regex]::Replace($t,$pat,$line)}else{if($t.Length -gt 0 -and !$t.EndsWith([Environment]::NewLine)){$t+=[Environment]::NewLine};$t+=$line+[Environment]::NewLine}};[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))" || (
  echo WARNING: Could not update bridge.conf automatically.
  echo Add these manually:
  echo   client.DirectInput.forward.mousePolicy = 3
  echo   client.DirectInput.forward.keyboardPolicy = 3
)

echo.
echo ============================================================
echo PATCHED DLL INSTALLED AND HASH-VERIFIED
echo IN-GAME DELETE-KEY VERIFICATION IS STILL REQUIRED
echo ============================================================
echo.
echo 1. Fully launch GTA IV again.
echo 2. Wait until the game reaches a rendered menu or gameplay scene.
echo 3. Press DELETE.
echo.
echo A CORRECT patched ReShade.log should contain:
echo   b-bridge input relay: accepting foreign render window
echo and then:
echo   b-bridge input relay: handshake complete

echo.
echo If ReShade.log instead says:
echo   Cannot capture input for window ... created by a different process

echo then STOCK ReShade is still loading and Step 3 is NOT complete.
echo.
echo To undo this patch later, simply double-click RESTORE_ORIGINAL.bat.
echo.
pause