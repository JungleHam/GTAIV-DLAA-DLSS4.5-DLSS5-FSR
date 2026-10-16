#define MyAppName "GTA IV Scaling"
#define MyAppVersion "1.2.4"
#define MyPublisher "JungleHam"
#define MyRepo "https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR"

[Setup]
AppId={{7E0329D7-03F6-4C99-9D92-C6757AF2E672}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyRepo}
AppSupportURL={#MyRepo}/issues
VersionInfoVersion=1.2.4.0
VersionInfoProductName=GTA IV Scaling
DefaultDirName={tmp}\GTAIV-Scaling-Setup
CreateAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=out
OutputBaseFilename=GTAIV-Scaling-Setup-v1.2.4
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
Uninstallable=no

[Files]
Source: "..\install\Install-DLAA.bat"; Flags: dontcopy
Source: "payload\Install-DLAA-Core-v1.2.4.bat"; Flags: dontcopy; DestName: "Install-DLAA-Core.bat"
Source: "..\install\Uninstall-DLAA.bat"; Flags: dontcopy
Source: "Run-Scaling-Action.ps1"; Flags: dontcopy
Source: "payload\GTAIV-Scaling-Runtime-v1.2.4.zip"; Flags: dontcopy
Source: "payload\ReShade64-bbridge.dll"; Flags: dontcopy

[Code]
var
  PrepPage: TOutputMsgMemoWizardPage;
  GamePage: TInputDirWizardPage;
  ActionPage: TInputOptionWizardPage;
  GpuPage: TOutputMsgWizardPage;
  ReShadePage: TInputFileWizardPage;
  ReShadeGitHubButton: TNewButton;
  OwnNrCheck: TNewCheckBox;
  OwnNrLabel: TNewStaticText;
  OwnNrEdit: TNewEdit;
  OwnNrBrowseButton: TNewButton;
  GameDir: string;
  SelectedAction: Integer;
  DetectedGpuSeries: Integer;
  FoundationPresent: Boolean;
  FusionFixInstalledThisRun: Boolean;

function QuoteArg(const S: string): string;
begin
  Result := '"' + S + '"';
end;

procedure OpenReShadeGitHub(Sender: TObject);
var ShellResult: Integer;
begin
  ShellExec('open', 'https://github.com/crosire/reshade', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
end;

function NormalizeGameDir(const Input: string): string;
var P: string;
begin
  P := RemoveBackslashUnlessRoot(Trim(Input));
  if FileExists(AddBackslash(P) + 'GTAIV.exe') then begin Result := P; exit; end;
  if FileExists(AddBackslash(P) + 'GTAIV\GTAIV.exe') then begin Result := AddBackslash(P) + 'GTAIV'; exit; end;
  Result := '';
end;

function DetectGpuSeries: Integer;
var PowerShell, Cmd: string; ResultCode: Integer;
begin
  Result := 0;
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Cmd := '$n=((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object {$_.Name -match ''(?i)NVIDIA.*RTX''} | Select-Object -First 1 -ExpandProperty Name)); if($n -match ''RTX\s*50''){exit 50}; if($n -match ''RTX\s*40''){exit 40}; if($n -match ''RTX\s*30''){exit 30}; if($n -match ''RTX\s*20''){exit 20}; if($n){exit 10}; exit 1';
  if Exec(PowerShell, '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command ' + QuoteArg(Cmd), '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    if ResultCode = 50 then Result := 50
    else if ResultCode = 40 then Result := 40
    else if ResultCode = 30 then Result := 30
    else if ResultCode = 20 then Result := 20
    else if ResultCode = 10 then Result := 10;
  end;
end;

function GpuSummary(Series: Integer): string;
begin
  if (Series = 20) or (Series = 30) or (Series = 40) or (Series = 50) or (Series = 10) then begin
    Result :=
      'NVIDIA RTX detected.' + #13#10 + #13#10 +
      'In-game scaling options:' + #13#10 +
      '  Off — Native' + #13#10 +
      '  NVIDIA DLAA / DLSS' + #13#10 +
      '  AMD FidelityFX FSR' + #13#10 + #13#10;
    if (Series = 20) or (Series = 30) or (Series = 40) or (Series = 50) then
      Result := Result + 'DLSS Neural Rendering will also be installed automatically and starts OFF.'
    else
      Result := Result + 'DLSS Neural Rendering is not installed on this RTX generation.';
  end
  else
    Result :=
      'No NVIDIA RTX GPU was detected.' + #13#10 + #13#10 +
      'In-game scaling options:' + #13#10 +
      '  Off — Native' + #13#10 +
      '  AMD FidelityFX FSR' + #13#10 + #13#10 +
      'The NVIDIA DLAA / DLSS option will be hidden.';
end;

function DetectFoundation(const Root: string): Boolean;
begin
  Result :=
    FileExists(AddBackslash(Root) + 'd3d9.dll') and
    FileExists(AddBackslash(Root) + '.trex\NvRemixBridge.exe') and
    FileExists(AddBackslash(Root) + '.trex\d3d9vk_x64.dll') and
    FileExists(AddBackslash(Root) + '.trex\dlss5-feed.addon64') and
    FileExists(AddBackslash(Root) + '.trex\ReShade.ini');
end;

procedure UpdateOwnNrControls;
var Visible: Boolean;
begin
  Visible := (SelectedAction = 0) and ((DetectedGpuSeries = 20) or (DetectedGpuSeries = 30) or (DetectedGpuSeries = 40) or (DetectedGpuSeries = 50));
  OwnNrCheck.Visible := Visible;
  OwnNrLabel.Visible := Visible and OwnNrCheck.Checked;
  OwnNrEdit.Visible := Visible and OwnNrCheck.Checked;
  OwnNrBrowseButton.Visible := Visible and OwnNrCheck.Checked;
end;

procedure OwnNrCheckClick(Sender: TObject);
begin
  UpdateOwnNrControls;
end;

procedure OwnNrBrowseClick(Sender: TObject);
var P: string;
begin
  P := OwnNrEdit.Text;
  if GetOpenFileName('Select nvngx_dlssnr.dll', P, '', 'DLL files|*.dll|All files|*.*', 'dll') then
    OwnNrEdit.Text := P;
end;

procedure InitializeWizard;
var PrepText: AnsiString;
begin
  WizardForm.Caption := '{#MyAppName} {#MyAppVersion}';
  FusionFixInstalledThisRun := False;
  SelectedAction := 0;
  DetectedGpuSeries := 0;

  PrepText :=
    'GTA IV Scaling 1.2.4 installs one complete scaling package.' + #13#10 + #13#10 +
    'The installer detects your GPU and the game only shows scaling backends that make sense on that machine.' + #13#10 + #13#10 +
    'NVIDIA RTX: Off / NVIDIA DLAA-DLSS / AMD FidelityFX FSR.' + #13#10 +
    'Non-RTX: Off / AMD FidelityFX FSR.' + #13#10 + #13#10 +
    'FusionFix and project dependencies are handled automatically. On a fresh setup you may only need to select the official ReShade 6.8.0 Full Add-On installer.';
  PrepPage := CreateOutputMsgMemoPage(wpWelcome, 'GTA IV Scaling 1.2.4', 'Unified install / repair', 'One package, runtime capability filtering.', PrepText);

  GamePage := CreateInputDirPage(PrepPage.ID, 'Select GTA IV', 'Choose the folder that contains GTAIV.exe', 'Select the GTA IV game folder.', False, '');
  GamePage.Add('');

  ActionPage := CreateInputOptionPage(GamePage.ID, 'Install or remove', 'Choose an action', 'Normal users should use Install / Repair.', True, False);
  ActionPage.Add('Install / Repair GTA IV Scaling 1.2.4');
  ActionPage.Add('Remove GTA IV Scaling, keep FusionFix');
  ActionPage.Add('Completely remove GTA IV Scaling and FusionFix');
  ActionPage.Values[0] := True;

  GpuPage := CreateOutputMsgPage(ActionPage.ID, 'GPU capability', 'Scaling backends that will be shown in-game', '');

  OwnNrCheck := TNewCheckBox.Create(WizardForm);
  OwnNrCheck.Parent := GpuPage.Surface;
  OwnNrCheck.Caption := 'I brought my own Neural Rendering DLL';
  OwnNrCheck.Left := ScaleX(0);
  OwnNrCheck.Top := GpuPage.MsgLabel.Top + GpuPage.MsgLabel.Height + ScaleY(18);
  OwnNrCheck.Width := ScaleX(280);
  OwnNrCheck.Checked := False;
  OwnNrCheck.OnClick := @OwnNrCheckClick;

  OwnNrLabel := TNewStaticText.Create(WizardForm);
  OwnNrLabel.Parent := GpuPage.Surface;
  OwnNrLabel.Caption := 'Path to nvngx_dlssnr.dll:';
  OwnNrLabel.Left := ScaleX(0);
  OwnNrLabel.Top := OwnNrCheck.Top + OwnNrCheck.Height + ScaleY(8);

  OwnNrEdit := TNewEdit.Create(WizardForm);
  OwnNrEdit.Parent := GpuPage.Surface;
  OwnNrEdit.Left := ScaleX(0);
  OwnNrEdit.Top := OwnNrLabel.Top + OwnNrLabel.Height + ScaleY(4);
  OwnNrEdit.Width := ScaleX(330);

  OwnNrBrowseButton := TNewButton.Create(WizardForm);
  OwnNrBrowseButton.Parent := GpuPage.Surface;
  OwnNrBrowseButton.Caption := 'Browse...';
  OwnNrBrowseButton.Left := OwnNrEdit.Left + OwnNrEdit.Width + ScaleX(8);
  OwnNrBrowseButton.Top := OwnNrEdit.Top - ScaleY(1);
  OwnNrBrowseButton.Width := ScaleX(80);
  OwnNrBrowseButton.OnClick := @OwnNrBrowseClick;

  ReShadePage := CreateInputFilePage(GpuPage.ID, 'Official ReShade prerequisite', 'Select ReShade 6.8.0 Full Add-On Support', 'Needed only when the GTA IV Scaling foundation is not already installed. Select the official ReShade setup EXE.');
  ReShadePage.Add('ReShade setup EXE:', 'Executable files|*.exe|All files|*.*', '.exe');

  ReShadeGitHubButton := TNewButton.Create(WizardForm);
  ReShadeGitHubButton.Parent := ReShadePage.Surface;
  ReShadeGitHubButton.Caption := 'Open ReShade repository on GitHub';
  ReShadeGitHubButton.Left := ReShadePage.Edits[0].Left;
  ReShadeGitHubButton.Top := ReShadePage.Edits[0].Top + ReShadePage.Edits[0].Height + ScaleY(12);
  ReShadeGitHubButton.Width := ScaleX(245);
  ReShadeGitHubButton.OnClick := @OpenReShadeGitHub;

  UpdateOwnNrControls;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = GpuPage.ID then
    Result := SelectedAction <> 0
  else if PageID = ReShadePage.ID then
    Result := (SelectedAction <> 0) or FoundationPresent or (not FileExists(AddBackslash(GameDir) + 'dinput8.dll'));
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
    FoundationPresent := DetectFoundation(GameDir);
  end
  else if CurPageID = ActionPage.ID then begin
    if ActionPage.Values[0] then SelectedAction := 0
    else if ActionPage.Values[1] then SelectedAction := 1
    else SelectedAction := 2;
    if SelectedAction = 0 then begin
      DetectedGpuSeries := DetectGpuSeries;
      GpuPage.MsgLabel.Caption := GpuSummary(DetectedGpuSeries);
      UpdateOwnNrControls;
    end;
  end
  else if CurPageID = GpuPage.ID then begin
    if OwnNrCheck.Visible and OwnNrCheck.Checked then begin
      if not FileExists(OwnNrEdit.Text) then begin
        MsgBox('Select nvngx_dlssnr.dll.', mbError, MB_OK);
        Result := False;
        exit;
      end;
      if CompareText(ExtractFileExt(OwnNrEdit.Text), '.dll') <> 0 then begin
        MsgBox('The Neural Rendering path must point to a DLL file.', mbError, MB_OK);
        Result := False;
        exit;
      end;
    end;
  end
  else if CurPageID = ReShadePage.ID then begin
    if not FileExists(ReShadePage.Values[0]) then begin
      MsgBox('Select the official ReShade 6.8.0 Full Add-On Support installer.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'GTA IV folder:' + NewLine + '  ' + GameDir + NewLine + NewLine;
  if SelectedAction = 0 then begin
    Result := Result + 'Action:' + NewLine + '  Install / Repair GTA IV Scaling 1.2.4' + NewLine + NewLine +
      'Package:' + NewLine +
      '  GTA IV Scaling runtime 1.2.4' + NewLine +
      '  NVIDIA DLAA / DLSS support files' + NewLine +
      '  AMD FidelityFX FSR' + NewLine +
      '  Matched bridge / presenter / ReShade input patch' + NewLine;
    if (DetectedGpuSeries = 20) or (DetectedGpuSeries = 30) or (DetectedGpuSeries = 40) or (DetectedGpuSeries = 50) then
      Result := Result + '  GPU-matched Neural Rendering runtime (starts OFF)' + NewLine;
    Result := Result + NewLine + GpuSummary(DetectedGpuSeries);
  end
  else if SelectedAction = 1 then
    Result := Result + 'Action:' + NewLine + '  Remove GTA IV Scaling, keep FusionFix' + NewLine +
      'This removes the scaling stack, .trex, ReShade project files, receipts, logs and backup folders, then restores the pre-scaling FusionFix state.' + NewLine
  else
    Result := Result + 'Action:' + NewLine + '  Completely remove GTA IV Scaling and FusionFix' + NewLine +
      'This performs the same scaling cleanup, then removes the pinned FusionFix package files too. Unrelated GTA IV mods are not intentionally removed.' + NewLine;
end;

procedure ExtractSetupFiles;
begin
  ExtractTemporaryFile('Install-DLAA.bat');
  ExtractTemporaryFile('Install-DLAA-Core.bat');
  ExtractTemporaryFile('Uninstall-DLAA.bat');
  ExtractTemporaryFile('Run-Scaling-Action.ps1');
  ExtractTemporaryFile('GTAIV-Scaling-Runtime-v1.2.4.zip');
  ExtractTemporaryFile('ReShade64-bbridge.dll');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PowerShell, Args, ResultPath, Detail, ActionName: string;
  RawDetail: AnsiString;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then begin
    ExtractSetupFiles;
    WizardForm.StatusLabel.Caption := 'Installing GTA IV Scaling 1.2.4...';

    PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    ResultPath := ExpandConstant('{tmp}\GTAIV-Scaling-action-result.txt');
    DeleteFile(ResultPath);

    if SelectedAction = 0 then ActionName := 'INSTALL'
    else if SelectedAction = 1 then ActionName := 'REMOVE_KEEP_FUSIONFIX'
    else ActionName := 'REMOVE_ALL';

    Args := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
      QuoteArg(ExpandConstant('{tmp}\Run-Scaling-Action.ps1')) +
      ' -Action ' + ActionName +
      ' -Game ' + QuoteArg(GameDir) +
      ' -RuntimePackage ' + QuoteArg(ExpandConstant('{tmp}\GTAIV-Scaling-Runtime-v1.2.4.zip')) +
      ' -ReShadePatch ' + QuoteArg(ExpandConstant('{tmp}\ReShade64-bbridge.dll')) +
      ' -ResultFile ' + QuoteArg(ResultPath);

    if (SelectedAction = 0) and (not FoundationPresent) and FileExists(ReShadePage.Values[0]) then
      Args := Args + ' -ReShadeSetup ' + QuoteArg(ReShadePage.Values[0]);

    if (SelectedAction = 0) and OwnNrCheck.Visible and OwnNrCheck.Checked then
      Args := Args + ' -NrPackage ' + QuoteArg(OwnNrEdit.Text);

    if not Exec(PowerShell, Args, GameDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Could not start the GTA IV Scaling setup action.');

    if ResultCode = 20 then begin
      FusionFixInstalledThisRun := True;
      exit;
    end;

    if ResultCode <> 0 then begin
      Detail := '';
      if LoadStringFromFile(ResultPath, RawDetail) then Detail := String(RawDetail);
      if Detail = '' then Detail := 'Unknown setup error. Check the setup console for the failing step.';
      RaiseException('Install failed:' + #13#10 + #13#10 + Detail);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if FusionFixInstalledThisRun then begin
      WizardForm.FinishedLabel.Caption := 'FusionFix 5.0.1 was installed. Launch GTA IV once to the main menu, close it, then run GTA IV Scaling Setup 1.2.4 again.';
      exit;
    end;

    if SelectedAction = 0 then
      WizardForm.FinishedLabel.Caption := 'GTA IV Scaling 1.2.4 is installed. Launch GTA IV, press Home, open Add-ons → GTA IV Scaling, and choose the scaling technology you want.'
    else if SelectedAction = 1 then
      WizardForm.FinishedLabel.Caption := 'GTA IV Scaling was removed. FusionFix was kept and restored to its pre-scaling state.'
    else
      WizardForm.FinishedLabel.Caption := 'GTA IV Scaling and FusionFix were removed. Unrelated GTA IV files/mods were left alone where possible.';
  end;
end;
