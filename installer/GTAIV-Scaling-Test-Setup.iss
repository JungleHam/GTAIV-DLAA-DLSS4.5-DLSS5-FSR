#define MyAppName "GTA IV Scaling Test Runtime"
#define MyAppVersion "1.2.10-test"
#define MyPublisher "JungleHam"
#define MyRepo "https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR"

[Setup]
AppId={{8C3E7D11-94AA-4C36-BA9D-1210F2C2B6A1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyRepo}
AppSupportURL={#MyRepo}/issues
VersionInfoVersion=1.2.10.0
VersionInfoProductName=GTA IV Scaling Test Runtime
DefaultDirName={tmp}\GTAIV-Scaling-Test-Setup
CreateAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=out-test
OutputBaseFilename=GTAIV-Scaling-1.2.10-Test-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
Uninstallable=no

[Files]
Source: "Install-Test-Runtime.ps1"; Flags: dontcopy
Source: "test-payload\GTAIV-DLSS-Full-Runtime.zip"; Flags: dontcopy

[Code]
var
  PrepPage: TOutputMsgMemoWizardPage;
  GamePage: TInputDirWizardPage;
  ActionPage: TInputOptionWizardPage;
  SocialClubPage: TInputOptionWizardPage;
  GameDir: string;
  SelectedAction: Integer;

function QuoteArg(const S: string): string;
begin
  Result := '"' + S + '"';
end;

function NormalizeGameDir(const Input: string): string;
var P: string;
begin
  P := RemoveBackslashUnlessRoot(Trim(Input));
  if FileExists(AddBackslash(P) + 'GTAIV.exe') then begin Result := P; exit; end;
  if FileExists(AddBackslash(P) + 'GTAIV\GTAIV.exe') then begin Result := AddBackslash(P) + 'GTAIV'; exit; end;
  Result := '';
end;

procedure InitializeWizard;
var PrepText: AnsiString;
begin
  WizardForm.Caption := '{#MyAppName} {#MyAppVersion}';
  SelectedAction := 0;
  PrepText :=
    'This is a TEST runtime update for an existing GTA IV Scaling v1.2.9 installation.' + #13#10 + #13#10 +
    'It updates the game-side bridge client, DXVK presenter and matched runtime files so we can test the Home-key and viewport diagnostics fixes.' + #13#10 + #13#10 +
    'An optional setting can make End open Rockstar Social Club without triggering ReShade; while enabled, End is reserved for that shortcut and Home remains ReShade's shortcut.' + #13#10 + #13#10 +
    'A timestamped backup of every file this updater changes is created inside your GTA IV folder. The installer also includes a Restore Previous Runtime option.' + #13#10 + #13#10 +
    'This is not a fresh-install package. It preserves FusionFix, your Neural Rendering DLL, M3K settings, ReShade.ini, ReShade presets and game mods.';
  PrepPage := CreateOutputMsgMemoPage(wpWelcome, 'GTA IV Scaling 1.2.10 TEST', 'Runtime update / rollback', 'For existing v1.2.9 installations only.', PrepText);

  GamePage := CreateInputDirPage(PrepPage.ID, 'Select GTA IV', 'Choose the folder that contains GTAIV.exe', 'Select the GTA IV game folder.', False, '');
  GamePage.Add('');

  ActionPage := CreateInputOptionPage(GamePage.ID, 'Install or restore', 'Choose an action', 'The previous runtime is backed up automatically.', True, False);
  ActionPage.Add('Install / repair the 1.2.10 test runtime');
  ActionPage.Add('Restore the previous runtime');
  ActionPage.Values[0] := True;

  SocialClubPage := CreateInputOptionPage(ActionPage.ID, 'Optional shortcut', 'Rockstar Social Club shortcut', 'Home opens ReShade. You can optionally reserve End for Rockstar Social Club.', False, False);
  SocialClubPage.Add('Use End for Rockstar Social Club (End is reserved; Home remains ReShade's shortcut).');
  SocialClubPage.Values[0] := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var P: string;
begin
  Result := True;
  if CurPageID = GamePage.ID then begin
    P := NormalizeGameDir(GamePage.Values[0]);
    if P = '' then begin
      MsgBox('GTAIV.exe was not found in that folder.', mbError, MB_OK);
      Result := False;
      exit;
    end;
    GameDir := P;
    GamePage.Values[0] := P;
  end else if CurPageID = ActionPage.ID then begin
    if ActionPage.Values[0] then SelectedAction := 0
    else if ActionPage.Values[1] then SelectedAction := 1
    else SelectedAction := 0;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = SocialClubPage.ID) and (SelectedAction <> 0);
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'GTA IV folder:' + NewLine + '  ' + GameDir + NewLine + NewLine;
  if SelectedAction = 0 then begin
    Result := Result + 'Action:' + NewLine + '  Install / repair 1.2.10 test runtime' + NewLine + NewLine +
      'A timestamped backup of the current v1.2.9 runtime files will be created first.' + NewLine +
      'Your existing ReShade and Neural Rendering settings will be preserved.' + NewLine + NewLine +
      'ReShade shortcut: Home remains unchanged.';
    if SocialClubPage.Values[0] then
      Result := Result + NewLine + 'Social Club shortcut: End sends a separate Home event to Rockstar without opening ReShade; End is reserved while GTA IV is focused.'
    else
      Result := Result + NewLine + 'Alternate Social Club shortcut: Disabled (native Home behavior unchanged).';
  end else
    Result := Result + 'Action:' + NewLine + '  Restore the previous runtime from the backup created by this installer.';
end;

procedure ExtractSetupFiles;
begin
  ExtractTemporaryFile('Install-Test-Runtime.ps1');
  ExtractTemporaryFile('GTAIV-DLSS-Full-Runtime.zip');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PowerShell, Args, ResultPath, Detail, ActionName: string;
  RawDetail: AnsiString;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then begin
    ExtractSetupFiles;
    WizardForm.StatusLabel.Caption := 'Applying GTA IV Scaling test runtime...';
    PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    ResultPath := ExpandConstant('{tmp}\GTAIV-Scaling-Test-result.txt');
    DeleteFile(ResultPath);
    if SelectedAction = 0 then ActionName := 'Install' else ActionName := 'Restore';

    Args := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
      QuoteArg(ExpandConstant('{tmp}\Install-Test-Runtime.ps1')) +
      ' -Action ' + ActionName +
      ' -Game ' + QuoteArg(GameDir) +
      ' -RuntimePackage ' + QuoteArg(ExpandConstant('{tmp}\GTAIV-DLSS-Full-Runtime.zip')) +
      ' -ResultFile ' + QuoteArg(ResultPath);

    if (SelectedAction = 0) and SocialClubPage.Values[0] then
      Args := Args + ' -SocialClubEndKey';

    if not Exec(PowerShell, Args, GameDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Could not start the GTA IV Scaling test runtime action.');
    if ResultCode <> 0 then begin
      Detail := '';
      if LoadStringFromFile(ResultPath, RawDetail) then Detail := String(RawDetail);
      if Detail = '' then Detail := 'Unknown setup error. Check the setup console for details.';
      RaiseException('Test runtime setup failed:' + #13#10 + #13#10 + Detail);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if SelectedAction = 0 then begin
      if SocialClubPage.Values[0] then
        WizardForm.FinishedLabel.Caption := 'GTA IV Scaling 1.2.10 test runtime installed. End opens Rockstar Social Club; Home remains ReShade's shortcut; F11 remains Steam's shortcut. End is reserved while GTA IV is focused. Test F11 / Steam overlay and DLAA scaling. Run this installer again and choose Restore Previous Runtime to roll back.'
      else
        WizardForm.FinishedLabel.Caption := 'GTA IV Scaling 1.2.10 test runtime installed. Home remains ReShade's shortcut; the Social Club alternate key is disabled. Test F11 / Steam overlay and DLAA scaling. Run this installer again and choose Restore Previous Runtime to roll back.';
    end else
      WizardForm.FinishedLabel.Caption := 'The previous GTA IV Scaling runtime has been restored. The backup was retained inside the GTA IV folder.';
  end;
end;
