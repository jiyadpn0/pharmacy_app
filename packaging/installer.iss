; Script generated for Sahakar Pharmacy ERP
; Inno Setup 6+ Production Installer Script

#define MyAppName "Sahakar Pharmacy ERP"
#define MyAppVersion "3.6.2"
#define MyAppPublisher "Sahakar Healthcare Systems"
#define MyAppURL "https://github.com/jiyadpn0/pharmacy_app"
#define MyAppExeName "pharmacy_app.exe"
#define SourceDir "..\build\windows\x64\runner\Release"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
AppId={{D8C86A80-7798-4B8F-9C1C-E73F2241F830}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Sahakar Pharmacy ERP
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}
; Store and retrieve license, architecture, and permissions
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=PharmacyERP_v{#MyAppVersion}_Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
AppMutex=SahakarPharmacyERPMutex
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "Create a &Quick Launch icon"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode

[Files]
; Main Executable
Source: "{#SourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Core Native DLLs
Source: "{#SourceDir}\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\dartjni.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\printing_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\desktop_multi_window_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\app_links_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
; Metadata files
Source: "{#SourceDir}\version.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\native_assets.json"; DestDir: "{app}"; Flags: ignoreversion
; Flutter Data Directory (AOT blob, flutter_assets, ICU data)
Source: "{#SourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Single instance check and graceful upgrade safeguard
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
