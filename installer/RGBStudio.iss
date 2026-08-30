#define MyAppName "RGB Studio"
#define MyAppVersion "0.1.0"
#define MyAppExeName "RGB Studio.exe"

[Setup]
AppId={{A15D7D97-4865-4FC2-AE89-46C810CCFE82}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=RGB Studio
DefaultDirName={autopf}\RGB Studio
DefaultGroupName=RGB Studio
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=RGB Studio Setup
SetupIconFile=..\assets\rgb-studio.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no
VersionInfoVersion=0.1.0.0
VersionInfoProductName=RGB Studio
VersionInfoDescription=RGB keyboard lighting editor and animation studio
VersionInfoCompany=RGB Studio

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho no Ambiente de Trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
Source: "..\publish\RGB Studio.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\RGB Studio"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\RGB Studio"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir RGB Studio"; Flags: nowait postinstall skipifsilent

[InstallDelete]
Type: files; Name: "{userdesktop}\MKMINIPRO Studio.lnk"

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
