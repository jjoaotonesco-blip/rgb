$ErrorActionPreference = 'Stop'
Get-Process MKMINIPRO -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$src = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public static class MkMiniRgbFps
{
    const uint DIGCF_PRESENT = 0x00000002;
    const uint DIGCF_DEVICEINTERFACE = 0x00000010;
    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS
    {
        public short Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public short[] Reserved;
        public short NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices;
        public short NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices;
        public short NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid HidGuid);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)] static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);
    [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, IntPtr DeviceInterfaceDetailData, uint DeviceInterfaceDetailDataSize, out uint RequiredSize, IntPtr DeviceInfoData);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(SafeFileHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(SafeFileHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CancelIoEx(SafeFileHandle hFile, IntPtr lpOverlapped);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_GetPreparsedData(SafeFileHandle HidDeviceObject, out IntPtr PreparsedData);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_FreePreparsedData(IntPtr PreparsedData);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr PreparsedData, out HIDP_CAPS Capabilities);

    static List<string> Paths()
    {
        var result = new List<string>(); Guid g; HidD_GetHidGuid(out g);
        IntPtr info = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
        if (info == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            for (uint i=0;;i++) {
                var d = new SP_DEVICE_INTERFACE_DATA(); d.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(info, IntPtr.Zero, ref g, i, ref d)) { int e=Marshal.GetLastWin32Error(); if(e==259) break; throw new Win32Exception(e); }
                uint need; SetupDiGetDeviceInterfaceDetail(info, ref d, IntPtr.Zero, 0, out need, IntPtr.Zero);
                IntPtr p=Marshal.AllocHGlobal((int)need);
                try { Marshal.WriteInt32(p, IntPtr.Size==8?8:6); if(!SetupDiGetDeviceInterfaceDetail(info,ref d,p,need,out need,IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error()); string s=Marshal.PtrToStringAuto(IntPtr.Add(p,4)); if(!String.IsNullOrEmpty(s)) result.Add(s); }
                finally { Marshal.FreeHGlobal(p); }
            }
        } finally { SetupDiDestroyDeviceInfoList(info); }
        return result;
    }

    static byte Sum(byte[] r) { int s=0; for(int i=5;i<65;i++) s+=r[i]; return (byte)(s&255); }
    static byte[] Simple(byte cmd) { var r=new byte[65]; r[1]=0x55; r[2]=cmd; r[4]=Sum(r); return r; }
    static byte[] Data(byte[] rgb,int off,int len) { var r=new byte[65]; r[1]=0x55; r[2]=0xDD; r[5]=(byte)len; r[6]=(byte)(off&255); r[7]=(byte)((off>>8)&255); Array.Copy(rgb,off,r,9,len); r[4]=Sum(r); return r; }

    class RR { public bool Ok; public int Err; public uint N; public byte[] Buf; }
    static void Ack(SafeFileHandle h)
    {
        byte[] b=new byte[65];
        Task<RR> t=Task.Factory.StartNew(()=>{ uint n; bool ok=ReadFile(h,b,65,out n,IntPtr.Zero); return new RR{Ok=ok,Err=ok?0:Marshal.GetLastWin32Error(),N=n,Buf=b}; });
        if(!t.Wait(100)) { CancelIoEx(h,IntPtr.Zero); throw new Exception("ACK timeout"); }
        RR rr=t.Result; if(!rr.Ok) throw new Win32Exception(rr.Err,"ACK read failed");
        bool ack=(rr.N>0&&b[0]==0xAA)||(rr.N>1&&b[1]==0xAA); if(!ack) throw new Exception("Missing ACK 0xAA");
    }
    static void Send(SafeFileHandle h,byte[] r) { uint w; if(!WriteFile(h,r,65,out w,IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error()); if(w!=65) throw new Exception("Short write"); Ack(h); }

    static byte[] Frame(byte r, byte g, byte b)
    {
        var rgb=new byte[384];
        // Use only known physical keys C, V, X to make the benchmark visible but not light the whole board.
        int[] idx={16,22,28};
        foreach(int i in idx) { rgb[i*3]=r; rgb[i*3+1]=g; rgb[i*3+2]=b; }
        return rgb;
    }

    static double SendFrame(SafeFileHandle h, byte[] rgb)
    {
        Stopwatch sw=Stopwatch.StartNew();
        Send(h,Simple(0x01));
        for(int c=0;c<7;c++){ int off=c*56; int len=c<6?56:48; Send(h,Data(rgb,off,len)); }
        Send(h,Simple(0x02));
        sw.Stop(); return sw.Elapsed.TotalMilliseconds;
    }

    public static void Run()
    {
        string target=null; foreach(string p in Paths()){ string q=p.ToLowerInvariant(); if(q.Contains("vid_5566")&&q.Contains("pid_0008")&&q.Contains("mi_02")) target=p; }
        if(target==null) throw new Exception("MI_02 not found");
        using(var h=CreateFile(target,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,IntPtr.Zero,OPEN_EXISTING,0,IntPtr.Zero))
        {
            if(h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr prep; if(!HidD_GetPreparsedData(h,out prep)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try { HIDP_CAPS caps; if(HidP_GetCaps(prep,out caps)<0) throw new Exception("HidP_GetCaps failed"); if(caps.InputReportByteLength!=65||caps.OutputReportByteLength!=65) throw new Exception("Unexpected HID report size"); }
            finally { HidD_FreePreparsedData(prep); }

            byte[] a=Frame(255,0,0), b=Frame(0,0,255);
            const int warmup=3, frames=30;
            for(int i=0;i<warmup;i++) SendFrame(h,(i&1)==0?a:b);
            double total=0,min=999999,max=0;
            for(int i=0;i<frames;i++) {
                double ms=SendFrame(h,(i&1)==0?a:b); total+=ms; if(ms<min)min=ms; if(ms>max)max=ms;
                Console.WriteLine("FRAME "+(i+1)+" ms="+ms.ToString("F2")+" fps="+(1000.0/ms).ToString("F1"));
            }
            double avg=total/frames;
            Console.WriteLine("RESULT avg_ms="+avg.ToString("F2")+" avg_fps="+(1000.0/avg).ToString("F2")+" min_ms="+min.ToString("F2")+" max_ms="+max.ToString("F2"));
            Console.WriteLine("NOTE: benchmark alternated C/V/X between red and blue for 30 frames, waiting for every ACK.");
        }
    }
}
'@

Add-Type -TypeDefinition $src -Language CSharp
[MkMiniRgbFps]::Run()
