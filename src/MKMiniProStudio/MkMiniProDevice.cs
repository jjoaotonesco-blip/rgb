using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace MKMiniProStudio;

internal sealed class MkMiniProDevice : IDisposable
{
    const uint DIGCF_PRESENT = 0x2, DIGCF_DEVICEINTERFACE = 0x10;
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
    readonly SemaphoreSlim gate = new(1, 1);

    [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)] struct HIDP_CAPS
    {
        public short Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public short[] Reserved;
        public short NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices,
            NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices, NumberFeatureButtonCaps,
            NumberFeatureValueCaps, NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr w, uint flags);
    [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr dev, ref Guid g, uint index, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, uint size, out uint needed, IntPtr dev);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint mode, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(SafeFileHandle h, byte[] b, uint n, out uint written, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(SafeFileHandle h, byte[] b, uint n, out uint read, IntPtr ov);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr p);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_FreePreparsedData(IntPtr p);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr p, out HIDP_CAPS caps);

    public static bool IsPresent() => FindPath() is not null;

    public async Task SendFrameAsync(byte[] rgb384, CancellationToken ct = default)
    {
        if (rgb384.Length != 384) throw new ArgumentException("RGB frame must be exactly 384 bytes.", nameof(rgb384));
        await gate.WaitAsync(ct);
        try { await Task.Run(() => SendFrame(rgb384, ct), ct); }
        finally { gate.Release(); }
    }

    // Official MKMINIPRO section 7 / Custom lighting path. Unlike 0xDD live preview,
    // command 0x0B stores the custom per-key map used by the keyboard after preview ends.
    public async Task SendPersistentFrameAsync(byte[] rgb384, CancellationToken ct = default)
    {
        if (rgb384.Length != 384) throw new ArgumentException("RGB frame must be exactly 384 bytes.", nameof(rgb384));
        await gate.WaitAsync(ct);
        try { await Task.Run(() => SendPersistentFrame(rgb384, ct), ct); }
        finally { gate.Release(); }
    }

    void SendFrame(byte[] rgb, CancellationToken ct)
    {
        var path = FindPath() ?? throw new InvalidOperationException("MKMINIPRO não encontrado (VID 5566 / PID 0008 / MI_02). Liga o teclado e tenta novamente.");
        using var h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Não foi possível abrir o RGB do MKMINIPRO. Fecha o software oficial da Mars e tenta novamente.");
        ValidateCaps(h);
        SendAck(h, Simple(0x01), "BEGIN", ct);
        for (int chunk=0; chunk<7; chunk++)
        {
            int offset=chunk*56, len=chunk<6 ? 56 : 48;
            SendAck(h, Data(rgb, offset, len), $"DATA {chunk}", ct);
        }
        SendAck(h, Simple(0x02), "APPLY", ct);
    }

    void SendPersistentFrame(byte[] rgb, CancellationToken ct)
    {
        var path = FindPath() ?? throw new InvalidOperationException("MKMINIPRO não encontrado (VID 5566 / PID 0008 / MI_02). Liga o teclado e tenta novamente.");
        using var h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Não foi possível abrir o RGB do MKMINIPRO. Fecha o software oficial da Mars e tenta novamente.");
        ValidateCaps(h);
        SendAck(h, Simple(0x01), "BEGIN CUSTOM", ct);
        for (int chunk=0; chunk<7; chunk++)
        {
            int offset=chunk*56, len=chunk<6 ? 56 : 48;
            SendAck(h, Data(rgb, offset, len, 0x0B), $"CUSTOM DATA {chunk}", ct);
        }
        SendAck(h, Simple(0x02), "APPLY CUSTOM", ct);
    }

    static void ValidateCaps(SafeFileHandle h)
    {
        if (!HidD_GetPreparsedData(h, out var p)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            if (HidP_GetCaps(p, out var c) < 0 || c.InputReportByteLength != 65 || c.OutputReportByteLength != 65)
                throw new InvalidOperationException("Interface HID inesperada; envio RGB cancelado por segurança.");
        }
        finally { HidD_FreePreparsedData(p); }
    }

    static void SendAck(SafeFileHandle h, byte[] report, string label, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if (!WriteFile(h, report, 65, out var written, IntPtr.Zero) || written != 65)
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"Falha no envio {label}");
        var response = new byte[65];
        if (!ReadFile(h, response, 65, out var read, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error(), $"Falha a ler ACK {label}");
        if (read < 2 || response[1] != 0xAA) throw new IOException($"ACK inválido em {label}");
    }

    static byte[] Simple(byte cmd)
    {
        var r=new byte[65]; r[1]=0x55; r[2]=cmd; r[4]=Checksum(r); return r;
    }
    static byte[] Data(byte[] rgb, int offset, int len, byte command = 0xDD)
    {
        var r=new byte[65]; r[1]=0x55; r[2]=command; r[5]=(byte)len; r[6]=(byte)offset; r[7]=(byte)(offset>>8);
        Array.Copy(rgb, offset, r, 9, len); r[4]=Checksum(r); return r;
    }
    static byte Checksum(byte[] r) { int s=0; for(int i=5;i<65;i++) s+=r[i]; return (byte)(s&0xFF); }

    static string? FindPath()
    {
        HidD_GetHidGuid(out var g);
        var set=SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
        if (set == new IntPtr(-1)) return null;
        try
        {
            for(uint i=0;;i++)
            {
                var d=new SP_DEVICE_INTERFACE_DATA { cbSize=Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>() };
                if(!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref d))
                {
                    if(Marshal.GetLastWin32Error()==259) break;
                    continue;
                }
                SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out var needed, IntPtr.Zero);
                var mem=Marshal.AllocHGlobal((int)needed);
                try
                {
                    Marshal.WriteInt32(mem, IntPtr.Size==8 ? 8 : 6);
                    if(!SetupDiGetDeviceInterfaceDetail(set, ref d, mem, needed, out _, IntPtr.Zero)) continue;
                    var p=Marshal.PtrToStringAuto(IntPtr.Add(mem,4));
                    if(p is not null)
                    {
                        var q=p.ToLowerInvariant();
                        if(q.Contains("vid_5566") && q.Contains("pid_0008") && q.Contains("mi_02")) return p;
                    }
                }
                finally { Marshal.FreeHGlobal(mem); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return null;
    }

    public void Dispose() => gate.Dispose();
}
