; =====================================================================
; Inno Setup Script for Pharmacy ERP & POS Desktop System
; =====================================================================

#define MyAppName "Pharmacy ERP & POS"
#define MyAppVersion "3.3.9"
#define MyAppPublisher "Pharmacy Systems Ltd."
#define MyAppURL "https://example.com"
#define MyAppExeName "pharmacy_app.exe"

[Setup]
; Unique App ID for Windows Installation tracking
AppId={{D37A8C2B-4E1F-4302-880B-4D8B9285038F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; Output setup.exe details
OutputDir=..\..\build\installer
OutputBaseFilename=Pharmacy_ERP_Setup_v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Source files built by `flutter build windows --release`
Source: "..\..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Ensures user SQLite database in %APPDATA%\PharmacyApp is preserved during uninstall
procedure CurUninstallStepChanged(UninstallStep: TUninstallStep);
begin
  if UninstallStep = usPostUninstall then
  begin
    // Intentionally keep user database and local backups intact
  end;
end;
