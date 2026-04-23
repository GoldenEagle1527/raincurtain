#define MyAppName "雨幕"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "GoldenEaglePersonal"
#define MyAppExeName "raincurtain.exe"
#define MyAppSourceDir "build\windows\x64\runner\Release"

[Setup]
AppId={{B9A2E8C1-7D4F-4B3A-9C2E-1F8D5A6B7C8D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=RainCurtain-Installer-{#MyAppVersion}
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
MinVersion=10.0
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
; 根据要求：不要单例检测
; AppMutex=

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"

[Tasks]
; 根据要求：默认勾选创建快捷方式(但是如果第一次安装的时候选择了取消,后续升级也不会再出现)
; Inno Setup 默认开启 UsePreviousTasks=yes，因此升级时会记住用户的选择，如果取消了就不会再创建
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#MyAppSourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#MyAppSourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 根据要求：安装后不显示打开程序选项
; 这里不添加 postinstall 标志的 Run 条目
