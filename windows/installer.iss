[Setup]
AppName=YueLink
AppVersion={#MyAppVersion}
AppPublisher=Yue.to
AppPublisherURL=https://yue.to
DefaultDirName={autopf}\YueLink
DefaultGroupName=YueLink
OutputDir=.
OutputBaseFilename=YueLink-Windows-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\yuelink.exe
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\YueLink"; Filename: "{app}\yuelink.exe"
Name: "{group}\Uninstall YueLink"; Filename: "{uninstallexe}"
Name: "{autodesktop}\YueLink"; Filename: "{app}\yuelink.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\yuelink.exe"; Description: "Launch YueLink"; Flags: nowait postinstall skipifsilent
