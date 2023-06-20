<#
Copyright (c) 2023 Steffen Illhardt
https://github.com/german-one/termwnd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

# min. req.: PowerShell v.2

try { Add-Type -EA SilentlyContinue -TypeDefinition @'
  using System;
  using System.Diagnostics;
  using System.IO;
  using System.Runtime.ConstrainedExecution;
  using System.Runtime.InteropServices;
  using System.Text;
  using System.Threading;

  //# provides properties identifying the terminal window the current console application is running in
  public static class WinTerm {
    //# imports the used Windows API functions
    private static class NativeMethods {
      [DllImport("kernel32.dll")]
      internal static extern int CloseHandle(IntPtr Hndl);
      [DllImport("kernelbase.dll")]
      internal static extern int CompareObjectHandles(IntPtr hFirst, IntPtr hSecond);
      [DllImport("kernel32.dll")]
      internal static extern int DuplicateHandle(IntPtr SrcProcHndl, IntPtr SrcHndl, IntPtr TrgtProcHndl, out IntPtr TrgtHndl, int Acc, int Inherit, int Opts);
      [DllImport("user32.dll")]
      [return: MarshalAs(UnmanagedType.Bool)]
      internal static extern bool EnumWindows(EnumWindowsProc enumFunc, IntPtr lparam);
      [DllImport("user32.dll")]
      internal static extern IntPtr GetAncestor(IntPtr hWnd, int flgs);
      [DllImport("kernel32.dll")]
      internal static extern IntPtr GetConsoleWindow();
      [DllImport("kernel32.dll")]
      internal static extern IntPtr GetCurrentProcess();
      [DllImport("user32.dll")]
      internal static extern IntPtr GetWindow(IntPtr hWnd, int cmd);
      [DllImport("user32.dll")]
      internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint procId);
      [DllImport("ntdll.dll")]
      internal static extern int NtQuerySystemInformation(int SysInfClass, IntPtr SysInf, int SysInfLen, out int RetLen);
      [DllImport("kernel32.dll")]
      internal static extern IntPtr OpenProcess(int Acc, int Inherit, uint ProcId);
      [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
      internal static extern int QueryFullProcessImageNameW(IntPtr Proc, int Flgs, StringBuilder Name, ref int Size);
      [DllImport("user32.dll")]
      internal static extern IntPtr SendMessageW(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    }

    private static readonly IntPtr conWnd = NativeMethods.GetConsoleWindow();

    public static IntPtr HWnd { get { return hWnd; } } //# window handle
    public static uint Pid { get { return pid; } } //# process id
    public static uint Tid { get { return tid; } } //# thread id
    public static string BaseName { get { return baseName; } } //# process name without .exe extension

    private static IntPtr hWnd = IntPtr.Zero;
    private static uint pid = 0;
    private static uint tid = 0;
    private static string baseName = string.Empty;

    //# owns an unmanaged resource
    //# the ctor qualifies a SafeRes object to manage either a pointer received from Marshal.AllocHGlobal(), or a handle
    private class SafeRes : CriticalFinalizerObject, IDisposable {
      //# resource type of a SafeRes object
      internal enum ResType { MemoryPointer, Handle }

      private IntPtr raw = IntPtr.Zero;
      private readonly ResType resourceType = ResType.MemoryPointer;

      internal IntPtr Raw { get { return raw; } }
      internal bool IsInvalid { get { return raw == IntPtr.Zero || raw == new IntPtr(-1); } }

      //# constructs a SafeRes object from an unmanaged resource specified by parameter raw
      //# the resource must be either a pointer received from Marshal.AllocHGlobal() (specify resourceType ResType.MemoryPointer),
      //# or a handle (specify resourceType ResType.Handle)
      internal SafeRes(IntPtr raw, ResType resourceType) {
        this.raw = raw;
        this.resourceType = resourceType;
      }

      ~SafeRes() { Dispose(false); }

      public void Dispose() {
        Dispose(true);
        GC.SuppressFinalize(this);
      }

      protected virtual void Dispose(bool disposing) {
        if (IsInvalid) { return; }
        if (resourceType == ResType.MemoryPointer) {
          Marshal.FreeHGlobal(raw);
          raw = IntPtr.Zero;
          return;
        }

        if (NativeMethods.CloseHandle(raw) != 0) { raw = new IntPtr(-1); }
      }

      internal virtual void Reset(IntPtr raw) {
        Dispose();
        this.raw = raw;
      }
    }

    //# undocumented SYSTEM_HANDLE structure, SYSTEM_HANDLE_TABLE_ENTRY_INFO might be the actual name
    [StructLayout(LayoutKind.Sequential)]
    private struct SystemHandle {
      internal readonly uint ProcId; //# PID of the process the SYSTEM_HANDLE belongs to
      internal readonly byte ObjTypeId; //# identifier of the object
      internal readonly byte Flgs;
      internal readonly ushort Handle; //# value representing an opened handle in the process
      internal readonly IntPtr pObj;
      internal readonly uint Acc;
    }

    private static string GetProcBaseName(SafeRes sHProc) {
      int size = 1024;
      StringBuilder nameBuf = new StringBuilder(size);
      return NativeMethods.QueryFullProcessImageNameW(sHProc.Raw, 0, nameBuf, ref size) == 0 ? "" : Path.GetFileNameWithoutExtension(nameBuf.ToString(0, size));
    }

    //# Enumerate the opened handles in each process, select those that refer to the same process as findOpenProcId.
    //# Return the ID of the process that opened the handle if its name is the same as searchProcName,
    //# Return 0 if no such process is found.
    private static uint GetPidOfNamedProcWithOpenProcHandle(string searchProcName, uint findOpenProcId) {
      const int PROCESS_DUP_HANDLE = 0x0040, //# access right to duplicate handles
                PROCESS_QUERY_LIMITED_INFORMATION = 0x1000, //# access right to retrieve certain process information
                STATUS_INFO_LENGTH_MISMATCH = unchecked((int)0xc0000004), //# NTSTATUS returned if we still didn't allocate enough memory
                SystemHandleInformation = 16; //# one of the SYSTEM_INFORMATION_CLASS values
      const byte OB_TYPE_INDEX_JOB = 7; //# one of the SYSTEM_HANDLE.ObjTypeId values
      int status, //# retrieves the NTSTATUS return value
          infSize = 0x200000, //# initially allocated memory size for the SYSTEM_HANDLE_INFORMATION object
          len;

      //# allocate some memory representing an undocumented SYSTEM_HANDLE_INFORMATION object, which can't be meaningfully declared in C# code
      using (SafeRes sPSysHndlInf = new SafeRes(Marshal.AllocHGlobal(infSize), SafeRes.ResType.MemoryPointer)) {
        //# try to get an array of all available SYSTEM_HANDLE objects, allocate more memory if necessary
        while ((status = NativeMethods.NtQuerySystemInformation(SystemHandleInformation, sPSysHndlInf.Raw, infSize, out len)) == STATUS_INFO_LENGTH_MISMATCH) {
          sPSysHndlInf.Reset(Marshal.AllocHGlobal(infSize = len + 0x1000));
        }

        if (status < 0) { return 0; }
        using (SafeRes sHFindOpenProc = new SafeRes(NativeMethods.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, findOpenProcId), SafeRes.ResType.Handle)) { //# intentionally after NtQuerySystemInformation() was called to exclude it from the found open handles
          if (sHFindOpenProc.IsInvalid) { return 0; }
          uint foundPid = 0, curPid = 0;
          IntPtr hThis = NativeMethods.GetCurrentProcess();
          int sysHndlSize = Marshal.SizeOf(typeof(SystemHandle));
          using (SafeRes sHCur = new SafeRes(IntPtr.Zero, SafeRes.ResType.Handle)) {
            //# iterate over the array of SYSTEM_HANDLE objects, which begins at an offset of pointer size in the SYSTEM_HANDLE_INFORMATION object
            //# the number of SYSTEM_HANDLE objects is specified in the first 32 bits of the SYSTEM_HANDLE_INFORMATION object
            for (IntPtr pSysHndl = (IntPtr)((long)sPSysHndlInf.Raw + IntPtr.Size), pEnd = (IntPtr)((long)pSysHndl + Marshal.ReadInt32(sPSysHndlInf.Raw) * sysHndlSize);
                 pSysHndl != pEnd;
                 pSysHndl = (IntPtr)((long)pSysHndl + sysHndlSize)) {
              //# get one SYSTEM_HANDLE at a time
              SystemHandle sysHndl = (SystemHandle)Marshal.PtrToStructure(pSysHndl, typeof(SystemHandle));
              //# shortcut; OB_TYPE_INDEX_JOB is the identifier we are looking for, any other SYSTEM_HANDLE object is immediately ignored at this point
              if (sysHndl.ObjTypeId != OB_TYPE_INDEX_JOB) { continue; }
              //# every time the process changes, the previous handle needs to be closed and we open a new handle to the current process
              if (curPid != sysHndl.ProcId) {
                curPid = sysHndl.ProcId;
                sHCur.Reset(NativeMethods.OpenProcess(PROCESS_DUP_HANDLE | PROCESS_QUERY_LIMITED_INFORMATION, 0, curPid));
              }

              //# if the process has not been opened, or
              //# if duplicating the current one of its open handles fails, continue with the next SYSTEM_HANDLE object
              //# the duplicated handle is necessary to get information about the object (e.g. the process) it points to
              IntPtr hCurOpenDup;
              if (sHCur.IsInvalid ||
                  NativeMethods.DuplicateHandle(sHCur.Raw, (IntPtr)sysHndl.Handle, hThis, out hCurOpenDup, PROCESS_QUERY_LIMITED_INFORMATION, 0, 0) == 0) {
                continue;
              }

              using (SafeRes sHCurOpenDup = new SafeRes(hCurOpenDup, SafeRes.ResType.Handle)) {
                if (NativeMethods.CompareObjectHandles(sHCurOpenDup.Raw, sHFindOpenProc.Raw) != 0 && //# both the handle of the open process and the currently duplicated handle must refer to the same kernel object
                    searchProcName == GetProcBaseName(sHCur)) { //# the process name of the currently found process must meet the process name we are looking for
                  foundPid = curPid;
                  break;
                }
              }
            }
          }
          return foundPid;
        }
      }
    }

    private static uint findPid;
    private static IntPtr foundHWnd;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private static bool GetOpenConWndCallback(IntPtr hWnd, IntPtr lParam) {
      uint thisPid;
      uint thisTid = NativeMethods.GetWindowThreadProcessId(hWnd, out thisPid);
      if (thisTid == 0 || thisPid != findPid)
        return true;

      foundHWnd = hWnd;
      return false;
    }

    private static IntPtr GetOpenConWnd(uint termPid) {
      if (termPid == 0)
        return IntPtr.Zero;

      findPid = termPid;
      foundHWnd = IntPtr.Zero;
      NativeMethods.EnumWindows(new EnumWindowsProc(GetOpenConWndCallback), IntPtr.Zero);
      return foundHWnd;
    }

    private static IntPtr GetTermWnd(ref bool terminalExpected) {
      const int WM_GETICON = 0x007F,
                GW_OWNER = 4,
                GA_ROOTOWNER = 3;

      //# We don't have a proper way to figure out to what terminal app the Shell process
      //# is connected on the local machine:
      //# https://github.com/microsoft/terminal/issues/7434
      //# We're getting around this assuming we don't get an icon handle from the
      //# invisible Conhost window when the Shell is connected to Windows Terminal.
      terminalExpected = NativeMethods.SendMessageW(conWnd, WM_GETICON, IntPtr.Zero, IntPtr.Zero) == IntPtr.Zero;
      if (!terminalExpected)
        return conWnd;

      //# Polling because it may take some milliseconds for Terminal to create its window and take ownership of the hidden ConPTY window.
      IntPtr conOwner = IntPtr.Zero; //# FWIW this receives the terminal window our tab is created in, but it gets never updated if the tab is moved to another window.
      for (int i = 0; i < 200 && conOwner == IntPtr.Zero; ++i) {
        Thread.Sleep(5);
        conOwner = NativeMethods.GetWindow(conWnd, GW_OWNER);
      }

      //# Something went wrong if polling did not succeed within 1 second (e.g. it's not Windows Terminal).
      if (conOwner == IntPtr.Zero)
        return IntPtr.Zero;

      //# Get the ID of the Shell process that spawned the Conhost process.
      uint shellPid;
      uint shellTid = NativeMethods.GetWindowThreadProcessId(conWnd, out shellPid);
      if (shellTid == 0)
        return IntPtr.Zero;

      //# Get the ID of the OpenConsole process spawned for the Shell process.
      uint openConPid = GetPidOfNamedProcWithOpenProcHandle("OpenConsole", shellPid);
      if (openConPid == 0)
        return IntPtr.Zero;

      //# Get the hidden window of the OpenConsole process
      IntPtr openConWnd = GetOpenConWnd(openConPid);
      if (openConWnd == IntPtr.Zero)
        return IntPtr.Zero;

      //# The root owner window is the Terminal window.
      return NativeMethods.GetAncestor(openConWnd, GA_ROOTOWNER);
    }

    static WinTerm() {
      Refresh();
    }

    //# used to initially get or to update the properties if a terminal tab is moved to another window
    public static void Refresh() {
      const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
      bool terminalExpected = false;
      hWnd = GetTermWnd(ref terminalExpected);
      if (hWnd == IntPtr.Zero)
        throw new InvalidOperationException();

      tid = NativeMethods.GetWindowThreadProcessId(hWnd, out pid);
      if (tid == 0)
        throw new InvalidOperationException();

      using (SafeRes sHProc = new SafeRes(NativeMethods.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid), SafeRes.ResType.Handle)) {
        if (sHProc.IsInvalid)
          throw new InvalidOperationException();

        baseName = GetProcBaseName(sHProc);
      }

      if (string.IsNullOrEmpty(baseName) || (terminalExpected && baseName != "WindowsTerminal"))
        throw new InvalidOperationException();
    }
  }
'@ } catch {}

if ('WinTerm' -as [type]) {
  if ($true -and [WinTerm]::BaseName -and ([WinTerm]::BaseName -eq 'WindowsTerminal')) {
	  
    "Id:$([WinTerm]::Pid)"
    "ProcessName:$([WinTerm]::BaseName)"
    "MainWindowHandle:$([WinTerm]::HWnd)"
	
	#Start-Sleep 5 # [Terminal version >= 1.18] Gives you some time to move the tab out or attach it to another window.
    #[WinTerm]::Refresh()
  }
}