#define MyAppName "Nova RGB"
#define MyAppVersion "0.2.0"
#define MyAppExeName "Nova RGB.exe"

[Setup]
AppId={{C780F6E4-71C6-4C29-B14E-2B64F3D99E58}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Nova RGB
DefaultDirName={autopf}\Nova RGB
DefaultGroupName=Nova RGB
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Nova RGB Setup
SetupIconFile=..\assets\nova-rgb.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName=Nova RGB
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no
VersionInfoVersion=0.2.0.0
VersionInfoProductName=Nova RGB
VersionInfoDescription=RGB keyboard lighting editor and animation studio
VersionInfoCompany=Nova RGB

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho no Ambiente de Trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
Source: "..\publish\Nova RGB.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Nova RGB"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Nova RGB"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir Nova RGB"; Flags: nowait postinstall skipifsilent

[InstallDelete]
Type: files; Name: "{userdesktop}\MKMINIPRO Studio.lnk"
Type: files; Name: "{userdesktop}\RGB Studio.lnk"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  OldExe: string;
begin
  if CurStep = ssPostInstall then
  begin
    OldExe := ExpandConstant('{userdocs}\MKMINIPRO Studio\App\MKMINIPRO Studio.exe');
    if FileExists(OldExe) then
      DeleteFile(OldExe);
  end;
end;
