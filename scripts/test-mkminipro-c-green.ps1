$ErrorActionPreference = 'Stop'

Get-Process MKMINIPRO -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$src = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public static class MkMiniRgbSingleKey
{
    const uint DIGCF_PRESENT = 0x00000002;
    const uint DIGCF_DEVICEINTERFACE = 0x00000010;
    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS
    {
        public short Usage;
        public short UsagePage;
        public short InputReportByteLength;
        public short OutputReportByteLength;
        public short FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public short[] Reserved;
        public short NumberLinkCollectionNodes;
        public short NumberInputButtonCaps;
        public short NumberInputValueCaps;
        public short NumberInputDataIndices;
        public short NumberOutputButtonCaps;
        public short NumberOutputValueCaps;
        public short NumberOutputDataIndices;
        public short NumberFeatureButtonCaps;
        public short NumberFeatureValueCaps;
        public short NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")]
    static extern void HidD_GetHidGuid(out Guid HidGuid);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, IntPtr DeviceInterfaceDetailData, uint DeviceInterfaceDetailDataSize, out uint RequiredSize, IntPtr DeviceInfoData);

    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(SafeFileHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(SafeFileHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CancelIoEx(SafeFileHandle hFile, IntPtr lpOverlapped);

    [DllImport("hid.dll", SetLastError = true)]
    static extern bool HidD_GetPreparsedData(SafeFileHandle HidDeviceObject, out IntPtr PreparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    static extern bool HidD_FreePreparsedData(IntPtr PreparsedData);

    [DllImport("hid.dll")]
    static extern int HidP_GetCaps(IntPtr PreparsedData, out HIDP_CAPS Capabilities);

    static List<string> EnumerateHidPaths()
    {
        var result = new List<string>();
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr info = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (info == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            uint index = 0;
            while (true)
            {
                var ifData = new SP_DEVICE_INTERFACE_DATA();
                ifData.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(info, IntPtr.Zero, ref hidGuid, index, ref ifData))
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 259) break;
                    throw new Win32Exception(err);
                }
                uint needed;
                SetupDiGetDeviceInterfaceDetail(info, ref ifData, IntPtr.Zero, 0, out needed, IntPtr.Zero);
                IntPtr detail = Marshal.AllocHGlobal((int)needed);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(info, ref ifData, detail, needed, out needed, IntPtr.Zero))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    string path = Marshal.PtrToStringAuto(IntPtr.Add(detail, 4));
                    if (!String.IsNullOrEmpty(path)) result.Add(path);
                }
                finally { Marshal.FreeHGlobal(detail); }
                index++;
            }
        }
        finally { SetupDiDestroyDeviceInfoList(info); }
        return result;
    }

    static byte Checksum(byte[] report)
    {
        int sum = 0;
        for (int i = 5; i < 65; i++) sum += report[i];
        return (byte)(sum & 0xFF);
    }

    static byte[] MakeSimple(byte command)
    {
        byte[] report = new byte[65];
        report[0] = 0x00;
        report[1] = 0x55;
        report[2] = command;
        report[3] = 0x00;
        report[4] = Checksum(report);
        return report;
    }

    static byte[] MakeData(byte[] rgb, int offset, int length)
    {
        byte[] report = new byte[65];
        report[0] = 0x00;
        report[1] = 0x55;
        report[2] = 0xDD;
        report[3] = 0x00;
        report[5] = (byte)length;
        report[6] = (byte)(offset & 0xFF);
        report[7] = (byte)((offset >> 8) & 0xFF);
        report[8] = 0x00;
        Array.Copy(rgb, offset, report, 9, length);
        report[4] = Checksum(report);
        return report;
    }

    class ReadResult
    {
        public bool Ok;
        public int Error;
        public uint Read;
    }

    static void ProbeAck(SafeFileHandle handle, string label)
    {
        byte[] response = new byte[65];
        Task<ReadResult> task = Task.Factory.StartNew(() =>
        {
            uint read;
            bool ok = ReadFile(handle, response, (uint)response.Length, out read, IntPtr.Zero);
            return new ReadResult { Ok = ok, Error = ok ? 0 : Marshal.GetLastWin32Error(), Read = read };
        });

        if (!task.Wait(250))
        {
            CancelIoEx(handle, IntPtr.Zero);
            Console.WriteLine(label + " ACK timeout; continuing with conservative delay");
            Thread.Sleep(60);
            return;
        }

        ReadResult rr = task.Result;
        if (!rr.Ok)
        {
            Console.WriteLine(label + " ACK read failed Win32=" + rr.Error + "; continuing with conservative delay");
            Thread.Sleep(60);
            return;
        }

        int count = (int)Math.Min(rr.Read, 8);
        string hex = BitConverter.ToString(response, 0, count);
        bool ack = (rr.Read > 0 && response[0] == 0xAA) || (rr.Read > 1 && response[1] == 0xAA);
        Console.WriteLine(label + " response=" + hex + " ACK=" + ack);
        Thread.Sleep(15);
    }

    static void Send(SafeFileHandle handle, byte[] report, string label)
    {
        uint written;
        if (!WriteFile(handle, report, (uint)report.Length, out written, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteFile failed for " + label);
        if (written != 65)
            throw new Exception(label + ": wrote " + written + " bytes; expected 65");
        Console.WriteLine(label + " write OK checksum=0x" + report[4].ToString("X2"));
        ProbeAck(handle, label);
    }

    public static void Run()
    {
        string target = null;
        foreach (string path in EnumerateHidPaths())
        {
            string lower = path.ToLowerInvariant();
            if (lower.Contains("vid_5566") && lower.Contains("pid_0008") && lower.Contains("mi_02"))
                target = path;
        }
        if (target == null) throw new Exception("Safety stop: VID_5566/PID_0008 MI_02 not found.");
        Console.WriteLine("Using: " + target);

        using (SafeFileHandle handle = CreateFile(target, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not open MI_02");

            IntPtr prep;
            if (!HidD_GetPreparsedData(handle, out prep)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                HIDP_CAPS caps;
                int status = HidP_GetCaps(prep, out caps);
                if (status < 0) throw new Exception("HidP_GetCaps failed status=" + status);
                Console.WriteLine("Input=" + caps.InputReportByteLength + " Output=" + caps.OutputReportByteLength + " Feature=" + caps.FeatureReportByteLength);
                if (caps.InputReportByteLength != 65 || caps.OutputReportByteLength != 65)
                    throw new Exception("Safety stop: expected 65-byte input/output reports.");
            }
            finally { HidD_FreePreparsedData(prep); }

            byte[] rgb = new byte[384];
            const int cIndex = 22;
            rgb[cIndex * 3 + 0] = 0;
            rgb[cIndex * 3 + 1] = 255;
            rgb[cIndex * 3 + 2] = 0;

            Console.WriteLine("Sending frame: only logical LED index 22 (C) = green; all other slots off.");
            Send(handle, MakeSimple(0x01), "BEGIN");
            for (int chunk = 0; chunk < 7; chunk++)
            {
                int offset = chunk * 56;
                int length = chunk < 6 ? 56 : 48;
                Send(handle, MakeData(rgb, offset, length), "DATA " + chunk);
            }
            Send(handle, MakeSimple(0x02), "APPLY");
            Console.WriteLine("DONE: expected result is only C green, everything else off.");
        }
    }
}
'@

Add-Type -TypeDefinition $src -Language CSharp
[MkMiniRgbSingleKey]::Run()
