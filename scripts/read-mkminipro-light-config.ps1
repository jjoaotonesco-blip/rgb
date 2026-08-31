$ErrorActionPreference = 'Stop'

# Post-reset diagnostic. Reuse the already validated HID P/Invoke implementation from the physical C-key test,
# but do NOT execute its Run() method and do NOT send any RGB/config write commands.
$basePath = Join-Path $PSScriptRoot 'test-mkminipro-c-green.ps1'
$text = Get-Content $basePath -Raw
$m = [regex]::Match($text, "(?s)\$src = @'\r?\n(.*?)\r?\n'@")
if (-not $m.Success) { throw 'Could not extract validated HID C# source.' }
$src = $m.Groups[1].Value

$method = @'
    public static void ReadLightingConfig()
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

            Send(handle, MakeSimple(0x01), "BEGIN");

            byte[] get = new byte[65];
            get[0] = 0x00;
            get[1] = 0x55;
            get[2] = 0x05;
            get[5] = 0x20;
            get[4] = Checksum(get);

            uint written;
            if (!WriteFile(handle, get, 65, out written, IntPtr.Zero) || written != 65)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GET05 WriteFile failed");
            Console.WriteLine("GET05 WRITE=" + BitConverter.ToString(get).Replace('-', ' '));

            byte[] response = new byte[65];
            uint read;
            if (!ReadFile(handle, response, 65, out read, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GET05 ReadFile failed");
            Console.WriteLine("GET05 READ COUNT=" + read);
            Console.WriteLine("GET05 READ=" + BitConverter.ToString(response, 0, (int)read).Replace('-', ' '));

            Send(handle, MakeSimple(0x02), "APPLY");
            Console.WriteLine("READ_ONLY_DONE");
        }
    }

'@

$needle = '    public static void Run()'
if (-not $src.Contains($needle)) { throw 'Run method marker missing.' }
$src = $src.Replace($needle, $method + $needle)

Add-Type -TypeDefinition $src -Language CSharp
[MkMiniRgbSingleKey]::ReadLightingConfig()
