; Inno Setup script for hermosa_pos (Windows)
; Build the app first:  flutter build windows --release
; Then compile this with Inno Setup (ISCC.exe hermosa_pos.iss)

#define MyAppName "Hermosa POS"
; Version is read from pubspec.yaml by CI and passed via /DMyAppVersion=...
; The literal below is only a fallback for local manual compiles.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.5"
#endif
#define MyAppPublisher "Hermosa"
#define MyAppExeName "Hermosa.exe"
; Folder that holds the Release output (relative to this .iss file)
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Stable GUID — identifies the app for upgrades/uninstall. Do NOT change
; once shipped, or Windows treats new versions as a separate product.
AppId={{B7E3F2A1-8C4D-4E9F-A1B2-9F3C2D1E4B05}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Default install location is C:\Program Files\Hermosa POS. The wizard
; STILL shows the "Select Destination Location" page so the user can
; change it (that page is on by default — we deliberately don't set
; DisableDirPage). Program Files lives on C: and is admin-protected.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=Output
OutputBaseFilename=HermosaPOS-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; POS app needs hardware access -> install for all users (Program Files)
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
; This is what creates the desktop shortcut, with a checkbox in the wizard
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; Copy the ENTIRE Release folder (exe + dlls + data\ flutter_assets)
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu entry
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
; Desktop shortcut (only if the task above is selected)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Hide the installed app files from the end user (the cashier should not
; see or tamper with the binaries). This runs automatically (no
; postinstall flag) right after the files are copied and shortcuts are
; created. Shortcuts and the uninstaller keep working — the hidden
; attribute doesn't block launching or uninstalling.
Filename: "{cmd}"; Parameters: "/C attrib +h ""{app}"" & attrib +h /S /D ""{app}\*"""; Flags: runhidden; StatusMsg: "Securing application files..."
; Optional "launch now" checkbox on the final page.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
