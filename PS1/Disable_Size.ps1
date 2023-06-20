<# disabling the cmd close button by batch command #>
<# https://stackoverflow.com/questions/13763134/disabling-the-cmd-close-button-by-batch-command #>

$code = @'
using System;
using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CloseButtonToggle {

 internal static class WinAPI {
   [DllImport("kernel32.dll")]
   internal static extern IntPtr GetConsoleWindow();

   [DllImport("user32.dll")]
   [return: MarshalAs(UnmanagedType.Bool)]
   internal static extern bool DeleteMenu(IntPtr hMenu,
                          uint uPosition, uint uFlags);

   [DllImport("user32.dll")]
   [return: MarshalAs(UnmanagedType.Bool)]
   internal static extern bool DrawMenuBar(IntPtr hWnd);

   [DllImport("user32.dll")]
   internal static extern IntPtr GetSystemMenu(IntPtr hWnd,
              [MarshalAs(UnmanagedType.Bool)]bool bRevert);

   const uint SC_CLOSE     = 0xF060;
   const uint SC_MAXIMIZE  = 0xF030;
   const uint SC_MINIMIZE  = 0xF020;
   const uint SC_SIZE      = 0xF000;
   const uint MF_BYCOMMAND = 0;

   internal static void ChangeCurrentState(IntPtr Console, bool state) {
     IntPtr hMenu = GetSystemMenu(Console, state);
	 DeleteMenu(hMenu, SC_SIZE, MF_BYCOMMAND);
	 DeleteMenu(hMenu, SC_MAXIMIZE, MF_BYCOMMAND);
     DrawMenuBar(Console);
   }
   internal static void ChangeCurrentState(bool state) {
	 IntPtr Console = GetConsoleWindow();
     IntPtr hMenu = GetSystemMenu(Console, state);
	 DeleteMenu(hMenu, SC_SIZE, MF_BYCOMMAND);
	 DeleteMenu(hMenu, SC_MAXIMIZE, MF_BYCOMMAND);
     DrawMenuBar(Console);
   }
 }

 public static class Status {
   public static void Disable(IntPtr Console) {
     WinAPI.ChangeCurrentState(Console, false); //its 'true' if need to enable
   }
   public static void Disable() {
     WinAPI.ChangeCurrentState(false); //its 'true' if need to enable
   }
 }
}
'@

Add-Type $code;
if (!($env:terminalFound)) {
	[CloseButtonToggle.Status]::Disable();
	exit;
}
if ($env:PROC_ID) {
	$ptr = @(Get-Process |where id -eq $env:PROC_ID).MainWindowHandle;
	[CloseButtonToggle.Status]::Disable($ptr);
	exit
}
if ($env:terminalFound) {
	foreach ($ptr in @(Get-Process -Name "windowsterminal" -ErrorAction SilentlyContinue).MainWindowHandle)  {
		[CloseButtonToggle.Status]::Disable($ptr);
	}
	exit
}