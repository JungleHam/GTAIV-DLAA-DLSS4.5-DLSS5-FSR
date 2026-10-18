#define AppName "GTA IV FusionFix Launcher"
#define AppVersion "1.0.0"

[Setup]
AppId={{DB81533A-3878-414A-BF8F-A9A67F2199C5}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=GTA IV Scaling Community Project
AppPublisherURL=https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR
VersionInfoVersion=1.0.0.0
DefaultDirName={tmp}\GTAIV-FusionFix-Latest
CreateAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=out
OutputBaseFilename=GTAIV-FusionFix-Latest-Launcher-v1.0.0
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
SetupLogging=yes
Uninstallable=no

[Files]
Source: "Install-Latest-FusionFix.ps1"; Flags: dontcopy

[Code]
var
  GamePage: TInputDirWizardPage;
  GameDir: String;

function Q(const Value: String): String;
begin
  Result := '"' + Value + '"';
end;

function NormalizeGamePath(const Value: String): String;
var Path: String;
begin
  Path := RemoveBackslashUnlessRoot(Trim(Value));
  if FileExists(AddBackslash(Path) + 'GTAIV.exe') then begin Result := Path; exit; end;
  if FileExists(AddBackslash(Path) + 'GTAIV\GTAIV.exe') then begin
    Result := AddBackslash(Path) + 'GTAIV'; exit;
  end;
  Result := '';
end;

procedure InitializeWizard();
begin
  WizardForm.WelcomeLabel2.Caption :=
    'Downloads the newest stable GTA IV FusionFix release directly from the official GitHub project.' + #13#10 + #13#10 +
    'The downloaded ZIP is checked against the official SHA-256 digest. Existing files are backed up, and FusionFix settings are preserved.' + #13#10 + #13#10 +
    'This does NOT install GTA IV Scaling, DLSS, FSR, DXVK, ReShade, or weapon mods.';

  GamePage := CreateInputDirPage(wpWelcome,
    'Choose GTA IV', 'Select the GTAIV.exe folder',
    'Select the GTA IV Complete Edition game directory. The latest stable FusionFix will be downloaded and installed there.',
    False, '');
  GamePage.Add('');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var P: String;
begin
  Result := True;
  if CurPageID = GamePage.ID then begin
    P := NormalizeGamePath(GamePage.Values[0]);
    if P = '' then begin
      MsgBox('The selected folder does not contain GTAIV.exe.', mbError, MB_OK);
      Result := False; exit;
    end;
    GameDir := P;
    GamePage.Values[0] := P;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'Action:' + NewLine +
    '  Install / Update latest stable FusionFix ONLY' + NewLine + NewLine +
    'Game directory:' + NewLine + '  ' + GameDir + NewLine + NewLine +
    'Source: ThirteenAG/GTAIV.EFLC.FusionFix releases/latest' + NewLine +
    'Verification: Official release asset SHA-256' + NewLine +
    'Existing configurations: Preserved' + NewLine +
    'Existing overwritten files: Backed up' + NewLine +
    'GTA IV Scaling and other mods: Not installed';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var PowerShell, Args, LogFile, Detail: String;
    RawDetail: AnsiString;
    ResultCode: Integer;
begin
  if CurStep <> ssInstall then exit;

  ExtractTemporaryFile('Install-Latest-FusionFix.ps1');
  WizardForm.StatusLabel.Caption := 'Checking latest stable FusionFix on GitHub...';
  LogFile := ExpandConstant('{tmp}\fusionfix-latest-result.txt');
  DeleteFile(LogFile);

  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Args := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
    Q(ExpandConstant('{tmp}\Install-Latest-FusionFix.ps1')) +
    ' -Game ' + Q(GameDir) +
    ' -ResultFile ' + Q(LogFile);

  if not Exec(PowerShell, Args, GameDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then
    RaiseException('Could not start the FusionFix installation script.');

  if ResultCode <> 0 then begin
    Detail := '';
    if LoadStringFromFile(LogFile, RawDetail) then Detail := String(RawDetail);
    if Detail = '' then Detail := 'Unknown error. Check the PowerShell installer window.';
    RaiseException('FusionFix installation failed:' + #13#10 + Detail);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption :=
      'FusionFix installation has finished. You can launch GTA IV now.' + #13#10 +
      'No GTA IV Scaling, ReShade, DXVK, or other mods were added.';
end;
