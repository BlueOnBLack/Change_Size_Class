:Change_Size
if defined AutoTask exit /b
if defined terminalFound (
  goto :Change_Size_T
)
goto :Change_Size_C
exit /b

:getDPI

rem Found a bug, set scalilng to 125,
rem than set custom scaling
rem now both option active via registry ??????

if not defined DpiValue (
  if defined Win8DpiScaling if !Win8DpiScaling! EQU 0x0 (exit /b)
)
if not defined Win8DpiScaling (
  if defined DpiValue if /i !DpiValue! EQU 0x0 (exit /b)
)

if defined DpiValue if defined Win8DpiScaling (
  if /i !Win8DpiScaling! EQU 0x0 if /i !DpiValue! EQU 0x0 (exit /b)
)

rem both can co-exist in same time
rem first set settings to 25% or 50%,
rem and set custom settings later,
rem so both settings co-exist in same time

if defined DpiValue if /i !DpiValue! NEQ 0x0 (
  
  rem it can only happen if set basic 25 50 or else
  rem and set custom settings later 
  
  if defined Win8DpiScaling if !Win8DpiScaling! EQU 0x1 goto :getDPI_
  
  rem we don't have Win8DpiScaling settings on
  rem so continue in 3. 2. 1. ................
  
  if /i !DpiValue! EQU 0x1 set "X_PERCEN=1.05"
  if /i !DpiValue! EQU 0x2 set "X_PERCEN=1.05"
  if /i !DpiValue! EQU 0x3 set "X_PERCEN=1.05"
  if /i !DpiValue! EQU 0x4 set "X_PERCEN=1.05"
  if /i !DpiValue! EQU 0x5 set "X_PERCEN=1.05"
  if /i !DpiValue! EQU 0x6 set "X_PERCEN=1.05"
  
  exit /b
)

:getDPI_

set output=
if defined LogPixels (
  %multinul% reg add HKCU\Software\Sysinternals\Hex2Dec /v EulaAccepted /f /d 1 /t reg_dword
  for /f "tokens=1,2 delims== " %%a in ('""%Hex2Dec%" /nobanner !LogPixels!"') do set /a "output=%%b+14"
)

if defined output (

  if !output! LSS 111 exit /b
  set /a LogPixels="!output!-100"
  
  :: A scaling table up to 125 Percent
  if /i !LogPixels! EQU 11 (set "X_PERCEN=1.02")
  if /i !LogPixels! EQU 12 (set "X_PERCEN=1.02")
  if /i !LogPixels! EQU 13 (set "X_PERCEN=1.1")
  if /i !LogPixels! EQU 14 (set "X_PERCEN=1.1")
  if /i !LogPixels! EQU 15 (set "X_PERCEN=1.11")
  if /i !LogPixels! EQU 16 (set "X_PERCEN=1.15")
  if /i !LogPixels! EQU 17 (set "X_PERCEN=1.15")
  if /i !LogPixels! EQU 18 (set "X_PERCEN=1.1")
  if /i !LogPixels! EQU 19 (set "X_PERCEN=1.1")
  if /i !LogPixels! EQU 20 (set "X_PERCEN=1.1")
  if /i !LogPixels! EQU 21 (set "X_PERCEN=1.13")
  if /i !LogPixels! EQU 22 (set "X_PERCEN=1.2")
  if /i !LogPixels! EQU 23 (set "X_PERCEN=1.2")
  if /i !LogPixels! EQU 24 (set "X_PERCEN=1.2")
  if /i !LogPixels! EQU 25 (set "X_PERCEN=1.24")
  if /i !LogPixels! EQU 26 (set "X_PERCEN=1.24")
  if /i !LogPixels! EQU 27 (set "X_PERCEN=1.21")
  if /i !LogPixels! EQU 28 (set "X_PERCEN=1.21")
  if /i !LogPixels! EQU 29 (set "X_PERCEN=1.21")
  if /i !LogPixels! EQU 30 (set "X_PERCEN=1.22")
  if /i !LogPixels! EQU 31 (set "X_PERCEN=1.24")
  if /i !LogPixels! EQU 32 (set "X_PERCEN=1.3")
  if /i !LogPixels! EQU 33 (set "X_PERCEN=1.3")
  if /i !LogPixels! EQU 34 (set "X_PERCEN=1.33")
  
  :: Above 126 Scaling
  if /i !LogPixels! GEQ 35 (set "X_PERCEN=1.07")
  
  exit /b
)

goto :eof

:Change_Size_C
rem Check current con size with mode con
(set Lines=)&(set Columns=)
for /f "tokens=1,2 delims=: " %%a in ('"%SingleNulV2% mode con"') do set "%%a=%%b"
if defined Lines if defined Columns (
  if !Lines! EQU %2 if !Columns! EQU %1 exit /b
  goto :Change_Size_C_
)

rem Check current con size with PowerShell
(set Width=)&(set Height=)
set COMMAND="@(get-host).ui.rawui.BufferSize.Width"
for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c !COMMAND!"`) do set /a "Width=%%#"
set COMMAND="@(get-host).ui.rawui.BufferSize.Height"
for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c !COMMAND!"`) do set /a "Height=%%#"
if defined Width if defined Height (
  if !Width! EQU %1 if !Height! EQU %2 exit /b
  goto :Change_Size_C_
)

:Change_Size_C_

rem try with mode con ......
rem [ this command clean the screen ]
mode con cols=%1 lines=%2
if !errorlevel! EQU 0 exit /b

rem try change screen size with PS,
rem [ this command not clean the screen, but borders look like shit ]
%SingleNulV2% %PowerShellEXE% -nop -c "[console]::WindowWidth=%1; [console]::WindowHeight=%2 ;"
exit /b

:Change_Size_T

rem Change screen under terminal window
rem using special PS script

set output=
set DpiValue=
set LogPixels=
set Win8DpiScaling=
set Monitor_Count=0
set Monitor_REG_PATH=

for /f "tokens=3 delims= " %%$ in ('"%SingleNulV2% reg query "HKCU\Control Panel\Desktop" /v LogPixels"') do set "LogPixels=%%$"
for /f "tokens=3 delims= " %%$ in ('"%SingleNulV2% reg query "HKCU\Control Panel\Desktop" /v Win8DpiScaling"') do set "Win8DpiScaling=%%$"


%multinul% reg query "HKCU\Control Panel\Desktop\PerMonitorSettings" && (
  for /f "tokens=*" %%$ in ('"%SingleNulV2% reg query "HKCU\Control Panel\Desktop\PerMonitorSettings""') do set /a Monitor_Count+=1
)

if !Monitor_Count! EQU 1 (
  for /f "tokens=*" %%$ in ('"%SingleNulV2% reg query "HKCU\Control Panel\Desktop\PerMonitorSettings""') do set "Monitor_REG_PATH=%%$"
)

if defined Monitor_REG_PATH (
  for /f "tokens=3 delims= " %%$ in ('"%SingleNulV2% reg query "!Monitor_REG_PATH!" /v "DpiValue""') do set "DpiValue=%%$"
)

if !Auto_Scaling! EQU 1 (
  if defined DpiValue       (call :getDPI & goto :Change_Size_T_NEXT)
  if defined Win8DpiScaling (call :getDPI & goto :Change_Size_T_NEXT)
)

:Change_Size_T_NEXT

REM VBScript - Numbers
REM https://www.tutorialspoint.com/vbscript/vbscript_numbers.htm

(set colss=) & (set lines=)
for /f "tokens=*" %%$ in ('"%SingleNulV2% %CscriptEXE% /nologo "%AritVBS%" %1 %C_FACTOR% %C_PERCEN% %X_PERCEN%"') do set "colss=%%$"
for /f "tokens=*" %%$ in ('"%SingleNulV2% %CscriptEXE% /nologo "%AritVBS%" %2 %L_FACTOR% %L_PERCEN% %X_PERCEN%"') do set "lines=%%$"
if defined colss if defined lines goto :Change_Size_T__

REM about Arithmetic Operators
REM https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_arithmetic_operators?view=powershell-7.3

(set colss=) & (set lines=)
for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c [math]::Round(%1*(%C_FACTOR%*%C_PERCEN%*%X_PERCEN%))"`) do set "colss=%%#"
for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c [math]::Round(%2*(%L_FACTOR%*%L_PERCEN%*%X_PERCEN%))"`) do set "lines=%%#"
if defined colss if defined lines goto :Change_Size_T__

cls
echo:
echo ERROR ### Can't set value for Lines / Columns
echo:
if not defined debugMode if not defined AutoTask pause
%SingleNul% timeout 2 /nobreak
goto:TheEndIsNear

:Change_Size_T__

:: reset hex value
set hex_val=

:: if we dont have handle, try change using ps custom code
if not defined Proc_Handle goto :Change_Size_T_

:: quick solution for v18 preview
:: new options to move out tabs .. wtf ...
:: MainWindowHandle can CHANGE every time ...
:: if tabs are moving etc etc etc

if defined Preview for /f "usebackq tokens=1,2 delims=:" %%a in (`"%SingleNulV2% %PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\termwnd_ps.ps1""`) do (^
if /i '%%a' EQU 'MainWindowHandle' if /i '%%b' NEQ '!Proc_Handle!' (set "Proc_Handle=%%b" && %MultiNul% %PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\Disable_Size.ps1"))

rem VBScript Hex Function
rem https://www.w3schools.com/asp/func_hex.asp

for /f "tokens=*" %%$ in ('"%SingleNulV2% %CscriptEXE% /nologo "%HeexVBS%" !Proc_Handle!"') do set "hex_val=%%$"
if defined hex_val goto :Change_Size_T_F

rem Undocumented Dynamic variables (read only)
rem https://ss64.com/nt/syntax-variables.html

set output=
call cmd /c exit /b !Proc_Handle!
set "output=!=exitcode!"
if defined output (
(echo "!output!" | %SingleNul% find /i "0000000") || (
  set "hex_val=0x!output:~1!"
  if "!output:~1,2!" EQU "00" set "hex_val=0x!output:~2!"
  goto :Change_Size_T_F
))

rem Base 16 (hexadecimal) to base 10 (decimal)
rem https://ninoburini.wordpress.com/2022/05/29/convert-numbers-between-base-10-decimal-and-base-16-hexadecimal-in-powershell/

set "output="
set "Command='{0:X}' -f [Int]($env:Proc_Handle)"
for /f "usebackq tokens=*" %%# in (`"%SingleNulV2% %PowerShellEXE% -nop -c !COMMAND!"`) do set "output=%%#"
if defined output ((set "hex_val=0x0!output!") & goto :Change_Size_T_F)

rem convert hex to decimal and vice versa with simple command-line utility
rem https://learn.microsoft.com/en-us/sysinternals/downloads/hex2dec

set "output="
%multinul% reg add HKCU\Software\Sysinternals\Hex2Dec /v EulaAccepted /f /d 1 /t reg_dword
for /f "tokens=1,2 delims== " %%a in ('"%SingleNulV2% "%Hex2Dec%" /nobanner !Proc_Handle!"') do set "output=%%b"
if defined output ((set "hex_val=!output:~0,2!0!output:~2!") & goto :Change_Size_T_F)

:: problem .......
goto :Change_Size_T_

:Change_Size_T_F
(%SingleNulV2% "%cmdow%" !hex_val! /SIZ !colss! !lines!) || goto :Change_Size_T_

set isVisible=
%multinul% del /q %Res______%
%PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\CheckWindowsStatus.ps1" >%Res______% %SingleNulV2%
if exist %Res______% (<%Res______% set /p isVisible=)
if defined isVisible if /i !isVisible! == False (
  :: re-start script under conhost ... 
  start "" "conhost" cmd /c "!OfficeRToolpath!\!OfficeRToolname!" -ForceConHost
  exit
)
exit /b

:Change_Size_T_

:: this function will look for PROC_ID value
%multinul% %PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\Set_Window.ps1"

set isVisible=
%multinul% del /q %Res______%
%PowerShellEXE% -nop -ep bypass -file "%ScriptDir%\CheckWindowsStatus.ps1" >%Res______% %SingleNulV2%
if exist %Res______% (<%Res______% set /p isVisible=)
if defined isVisible if /i !isVisible! == False (
  :: re-start script under conhost ... 
  start "" "conhost" cmd /c "!OfficeRToolpath!\!OfficeRToolname!" -ForceConHost
  exit
)

exit /b
