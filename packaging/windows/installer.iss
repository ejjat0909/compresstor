; Inno Setup script for Compresstor Windows installer
; Built by CI: scripts\build_windows.bat produces the app folder,
; then this script packages it into a single Setup exe.
; The setup.exe is code-signed AFTER this script runs (see
; build_windows.bat Stage 6 + docs\windows-code-signing.md).

#define MyAppName "Compresstor"
#define MyAppPublisher "ejjat0909"
#define MyAppURL "https://github.com/ejjat0909/compresstor"
#define MyAppExeName "compresstor.exe"

[Setup]
AppId={{7E2D3F4A-8B1C-4E5F-9A0D-6C7B8E9F0A1B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\release
OutputBaseFilename=Compresstor-{#MyAppVersion}-windows-setup
SetupIconFile=..\..\assets\icon\Compresstor.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\release\Windows\Compresstor\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
