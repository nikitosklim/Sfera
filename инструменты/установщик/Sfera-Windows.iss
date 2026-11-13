; Sfera-Windows.iss — установщик «Панели Сферы» для Windows (Inno Setup 6).
; Собирается скриптом собрать-релиз-windows.ps1:
;   ISCC.exe /DAppVersion=0.4.4 /DSourceDir=<папка Sfera-Panel-Windows> /DOutDir=<куда> Sfera-Windows.iss
; Ставит программу для текущего пользователя (права администратора не нужны; по желанию можно для всех),
; создаёт ярлыки в меню «Пуск» и по желанию на рабочем столе, добавляет запись в «Установку и удаление программ».
; Повторный запуск более нового установщика обновляет программу поверх (AppId тот же).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\релиз\Sfera-Panel-Windows"
#endif
#ifndef OutDir
  #define OutDir "..\..\релиз"
#endif

[Setup]
AppId={{6F1D3C52-5B7E-4E0A-9C84-3A1D2F7B8E41}
AppName=Панель Сферы
AppVersion={#AppVersion}
AppVerName=Панель Сферы {#AppVersion}
AppPublisher=Сфера
AppPublisherURL=https://языксфера.рф
AppSupportURL=https://языксфера.рф
DefaultDirName={autopf}\Sfera
DefaultGroupName=Сфера
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutDir}
OutputBaseFilename=Sfera-Setup-Windows-{#AppVersion}
SetupIconFile=..\иконки\Sfera.ico
UninstallDisplayIcon={app}\Sfera.ico
UninstallDisplayName=Панель Сферы
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoDescription=Установщик Панели Сферы

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "..\иконки\Sfera.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Панель Сферы"; Filename: "{app}\Sfera-Panel.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Sfera.ico"
Name: "{autodesktop}\Панель Сферы"; Filename: "{app}\Sfera-Panel.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Sfera.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\Sfera-Panel.exe"; WorkingDir: "{app}"; Description: "Запустить Панель Сферы"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Файлы «.old» остаются после самообновления панели.
Type: filesandordirs; Name: "{app}"
