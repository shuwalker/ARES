
[Setup]
AppId={{A8D7B4A2-6F1C-4E7A-93D4-E9C3F2B1A7D0}}
AppName=ARES
AppVersion=0.1.0
DefaultDirName={localappdata}\ARES
DisableProgramGroupPage=yes
OutputDir=C:/Users/Sean Jenkins/ARES/windows-app/dist
OutputBaseFilename=ARES-Setup
Compression=lzma
SolidCompression=yes

[Icons]
Name: "{autoprograms}\ARES"; Filename: "{app}\ARES.exe"
Name: "{autodesktop}\ARES"; Filename: "{app}\ARES.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ARES.exe"; Description: "Launch ARES"; Flags: nowait postinstall skipifsilent
