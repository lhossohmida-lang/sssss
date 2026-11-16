; مثبّت تطبيق الإدارة على Windows (Inno Setup 6). يُبنى في مسار GitHub لا يدوياً:
;   ISCC.exe /DAppVersion=preview-6 /DSourceDir=<مجلد Release> /DOutputDir=<مجلد الإخراج> tool\installer\admin.iss
;
; المجلد المصدر هو ناتج `flutter build windows --release` بعد أن ينسخ المسار إليه مكتبات Visual C++
; (vcruntime140.dll وmsvcp140.dll ...) ويتحقق tool\windows_dll_check.py أن لا DLL ناقصة؛ فيعمل المثبّت
; على جهاز نظيف دون Visual Studio ودون Visual C++ Redistributable ودون إنترنت.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\apps\admin\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; معرّف ثابت: يجعل المثبّت الجديد يحدّث النسخة المثبّتة بدل أن يثبّت نسخة ثانية.
AppId={{B2F0C3A4-5E71-4C1D-9A62-7D3B8E5F1A90}
AppName=School Admin
AppVersion={#AppVersion}
AppPublisher=School Management
VersionInfoVersion=1.0.0.0
DefaultDirName={autopf}\School Admin
DefaultGroupName=School Admin
DisableProgramGroupPage=yes
; تثبيت لمستخدم واحد دون صلاحيات مدير (لا نافذة UAC)، ويتيح المثبّت اختيار «كل المستخدمين» بصلاحيات مدير.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Flutter يتطلب Windows 10 وما بعده و64 بت.
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=school-admin-setup
SetupIconFile=..\..\apps\admin\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\admin.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; يغلق التطبيق إن كان يعمل أثناء التحديث. بيانات المدرسة تُحفظ خارج مجلد التثبيت فلا تُمسّ.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\School Admin"; Filename: "{app}\admin.exe"
Name: "{autodesktop}\School Admin"; Filename: "{app}\admin.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\admin.exe"; Description: "{cm:LaunchProgram,School Admin}"; Flags: nowait postinstall skipifsilent
; التحديث التلقائي: التطبيق يشغّل هذا المثبّت صامتاً مع /relaunch=1 ثم يغلق نفسه، فيُعاد فتح النسخة الجديدة.
Filename: "{app}\admin.exe"; Flags: nowait; Check: RelaunchRequested

[Code]
function RelaunchRequested: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
