:Terminal_Handle_Check

:: if terminal set to default,
:: every cmd windows will attach to main windowsterminal.exe window
:: the parent process will be expolorer.exe, not windowsterminal.exe

:: reset value
set "TerminalFound="

:: regular check
if not defined PID exit /b
if defined NT_X if !NT_X! LSS 10 exit /b

set "count="
set COMMAND="@(gcim win32_process | where Name -Match 'WindowsTerminal.exe').Count"
for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c !COMMAND!"`) do set /a "count=%%#"
if defined count if !count! LSS 1 exit /b

echo ### [!time!] Check for Terminal app [Handle Check]

:: PS1 method

:: Windows Terminal v17 - v18 [Preview] with new tab shit etc etc
for %%# in (Proc_ID,Proc_Name,Proc_Handle,ParentProcessId, Preview) do set "%%#="
for /f "usebackq tokens=1,2 delims=:" %%a in (`"%SingleNulV2% %PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\termwnd_ps.ps1""`) do (
  
  REM 'Id' - '972'
  REM 'ProcessName' - 'WindowsTerminal'
  REM 'MainWindowHandle' - '0x0e0270'
  
  if /i '%%a' EQU 'Id'               set "Proc_ID=%%b"
  if /i '%%a' EQU 'ProcessName'      set "Proc_Name=%%b"
  if /i '%%a' EQU 'MainWindowHandle' set "Proc_Handle=%%b"
)

if defined Proc_ID if defined Proc_Name if defined Proc_Handle (
  set terminalFound=*
  set Preview=*
  exit /b
)

:: Windows Terminal v12 - v13 - v14 - v15 - v16 - v17 - v18 [Preview]
for %%# in (Proc_ID,Proc_Name,Proc_Handle,ParentProcessId) do set "%%#="
for /f "usebackq tokens=1,2 delims=:" %%a in (`"%SingleNulV2% %PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\termproc_ps.ps1""`) do (
  
  REM 'Id' - '972'
  REM 'ProcessName' - 'WindowsTerminal'
  REM 'MainWindowHandle' - '0x0e0270'
  
  if /i '%%a' EQU 'Id'               set "Proc_ID=%%b"
  if /i '%%a' EQU 'ProcessName'      set "Proc_Name=%%b"
  if /i '%%a' EQU 'MainWindowHandle' set "Proc_Handle=%%b"
)

if defined Proc_ID if defined Proc_Name if defined Proc_Handle (
  set terminalFound=*
  exit /b
)

:: Manual method

for %%# in (Proc_ID,Proc_Name,Proc_Handle,ParentProcessId) do set "%%#="

if not defined PID (
  exit /b )

%multinul% del /q %Res______%
%multinul% reg add HKCU\Software\Sysinternals\Handle /v EulaAccepted /f /d 1 /t reg_dword

(%SingleNulV2% "%handle%" -nobanner -a -v "cmd.exe(!PID!)" -p "WindowsTerminal" | more +1 >%Res______%) || exit /b

REM get process -> ID
<%Res______% set /p result=
for /f "tokens=1,2,3,4,5 delims=," %%a in ('"echo !result!"') do set "Proc_ID=%%b"

if defined Proc_ID (
  set "terminalFound=*"
  REM get Process -> MainWindowHandle (using Get-process->MainWindowHandle)
  set COMMAND="@(Get-process | Where Id -EQ !Proc_ID!).MainWindowHandle"
  for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c !COMMAND!"`) do set "Proc_Handle=%%#"
)

if defined Proc_ID if defined Proc_Handle (
  set terminalFound=*
  exit /b
)

for %%# in (Proc_ID,Proc_Name,Proc_Handle,ParentProcessId) do set "%%#="
goto :eof
