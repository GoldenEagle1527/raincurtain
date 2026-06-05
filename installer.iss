#define MyAppName "雨幕"
#define MyAppVersion "1.2.5"
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
; 修改为 admin 权限以支持 VC++ 运行时安装
; 如果用户拒绝提权,安装器会提示手动安装运行时
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
; 根据要求：不要单例检测
; AppMutex=
; 安装前自动关闭正在运行的雨幕进程
CloseApplications=force
CloseApplicationsFilter=*.exe

; VC++ 运行时依赖检测与安装
[Code]
var
  VCRedistInstallFailed: Boolean;

function VCRedistNeedsInstall: Boolean;
var
  Version: String;
begin
  // 检查 VC++ 2015-2022 Redistributable (x64) 是否已安装
  // 注册表键值对应 14.30+ 版本 (包含 MSVCP140.dll)
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version) then
  begin
    Result := False; // 已安装
  end
  else
  begin
    Result := True; // 需要安装
  end;
end;

// 安装前强制关闭正在运行的雨幕进程
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  NeedsRestart := False;
  // 使用 taskkill 强制终止雨幕进程（忽略错误，因为进程可能未运行）
  Exec('taskkill.exe', '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // 等待一小段时间确保进程完全退出、文件句柄释放
  Sleep(500);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if VCRedistNeedsInstall then
    begin
      // 尝试静默安装 VC++ 运行时
      if not Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      begin
        VCRedistInstallFailed := True;
      end;
    end;
  end;
end;

procedure DeinitializeSetup();
var
  ErrorMsg: String;
begin
  if VCRedistInstallFailed then
  begin
    ErrorMsg := '警告：Visual C++ 运行库安装失败！' + #13#10 + #13#10 +
                '应用程序需要此运行库才能正常运行。' + #13#10 +
                '请手动安装 VC++ Redistributable:' + #13#10 + #13#10 +
                '1. 打开安装目录: ' + ExpandConstant('{app}') + #13#10 +
                '2. 运行 vc_redist.x64.exe' + #13#10 + #13#10 +
                '或从微软官网下载:' + #13#10 +
                'https://aka.ms/vs/17/release/vc_redist.x64.exe';
    MsgBox(ErrorMsg, mbError, MB_OK);
  end;
end;

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

; 嵌入 VC++ Redistributable 安装包 (需要手动下载放置到 redist 目录)
; 下载地址: https://aka.ms/vs/17/release/vc_redist.x64.exe
; 同时复制到安装目录供用户手动安装
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: VCRedistNeedsInstall
Source: "redist\vc_redist.x64.exe"; DestDir: "{app}"; Flags: ignoreversion; Check: VCRedistNeedsInstall

[InstallDelete]
; 安装前清理旧文件（可选）

[UninstallRun]
; 卸载前强制关闭雨幕进程
Filename: "taskkill.exe"; Parameters: "/F /IM {#MyAppExeName}"; Flags: runhidden; RunOnceId: "KillRainCurtain"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 注意：VC++ 运行时安装已移至 CurStepChanged 中处理
; 这样可以更好地捕获错误并提示用户

; 根据要求：安装后不显示打开程序选项
; 这里不添加 postinstall 标志的 Run 条目
