# read_msi_psu.ps1 0.3.0 - read live telemetry from an MSI MEG Ai1300P power supply and print one line of JSON.
# 讀取 MSI MEG Ai1300P 電源的即時讀數，輸出一行 JSON。
#
# Uses only the HID APIs built into Windows (PowerShell 5.1 + inline C#). Nothing to install, no admin rights needed.
# Sends only two READ commands: handshake FA 51 and "read all" 51 E0. It never sends write commands
# (the 50 xx family), so it cannot change any PSU setting.
# 只送兩種讀取指令（握手 FA 51、讀全部 51 E0），不送任何寫入指令，不會改電源設定。
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File read_msi_psu.ps1 [-ProductId 0x56D4]
#
# SPDX-License-Identifier: MIT
param([int]$ProductId = 0x56D4)
$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public static class MsiPsuHid {
    [StructLayout(LayoutKind.Sequential)]
    struct DevIfData { public int cbSize; public Guid cls; public int flags; public IntPtr reserved; }
    [StructLayout(LayoutKind.Sequential)]
    struct Caps { public short Usage, UsagePage, InLen, OutLen, FeatLen;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public short[] r; public short a,b,c,d,e,f,g,h,i,j; }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr p);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr p);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr p, ref Caps c);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr w, int f);
    [DllImport("setupapi.dll")] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref DevIfData x);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref DevIfData x, IntPtr buf, int size, out int need, IntPtr d);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll")] static extern bool CancelIoEx(SafeFileHandle h, IntPtr o);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFile(string n, uint acc, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);

    public static string FindPath(int vid, int pid) {
        Guid g; HidD_GetHidGuid(out g);
        IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12); // DIGCF_PRESENT | DIGCF_DEVICEINTERFACE
        string want = string.Format("vid_{0:x4}&pid_{1:x4}", vid, pid);
        try {
            for (int i = 0; ; i++) {
                var x = new DevIfData(); x.cbSize = Marshal.SizeOf(x);
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref x)) return null;
                int need; SetupDiGetDeviceInterfaceDetail(set, ref x, IntPtr.Zero, 0, out need, IntPtr.Zero);
                IntPtr buf = Marshal.AllocHGlobal(need);
                try {
                    Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref x, buf, need, out need, IntPtr.Zero)) continue;
                    string path = Marshal.PtrToStringUni(new IntPtr(buf.ToInt64() + 4));
                    if (path.ToLowerInvariant().Contains(want)) return path;
                } finally { Marshal.FreeHGlobal(buf); }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
    }

    // Send one command (prefixed with report ID 0) and read back the input report that echoes it.
    // Other software (e.g. MSI Center) may be polling the PSU at the same time, so replies to other
    // commands are discarded; up to 6 reports are read before giving up. Throws on timeout.
    // 送一個指令（前面補報告編號 0），讀回開頭照抄同一指令的回覆；別人的回覆丟掉，最多讀 6 份。
    static byte[] Ask(FileStream fs, int outLen, int inLen, byte[] cmd, int ms) {
        var o = new byte[outLen];
        Array.Copy(cmd, 0, o, 1, cmd.Length);
        fs.Write(o, 0, o.Length);
        var until = DateTime.UtcNow.AddMilliseconds(ms);
        for (int n = 0; n < 6; n++) {
            var r = new byte[inLen];
            int left = (int)(until - DateTime.UtcNow).TotalMilliseconds;
            Task<int> t = fs.ReadAsync(r, 0, r.Length);
            if (left <= 0 || !t.Wait(left)) throw new TimeoutException("PSU did not respond");
            for (int k = 0; k < 2; k++)
                if (r[k] == cmd[0] && (r[k + 1] == cmd[1] || r[k + 1] == 0xFE)) return r;
        }
        throw new IOException("kept receiving replies to other commands");
    }

    // Returns [handshake reply, read-all reply] as raw bytes; PowerShell decodes them.
    public static byte[][] Query(int vid, int pid, int ms) {
        string path = FindPath(vid, pid);
        if (path == null) throw new IOException("MSI PSU USB HID device not found");
        var h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero); // read/write, shared, OVERLAPPED
        if (h.IsInvalid) throw new IOException("cannot open USB device, Win32 error " + Marshal.GetLastWin32Error());
        IntPtr pre; var caps = new Caps(); caps.r = new short[17];
        if (!HidD_GetPreparsedData(h, out pre)) throw new IOException("cannot read HID descriptor");
        try { HidP_GetCaps(pre, ref caps); } finally { HidD_FreePreparsedData(pre); }
        var fs = new FileStream(h, FileAccess.ReadWrite, 4096, true);
        try {
            var hs = Ask(fs, caps.OutLen, caps.InLen, new byte[] { 0xFA, 0x51 }, ms);
            var all = Ask(fs, caps.OutLen, caps.InLen, new byte[] { 0x51, 0xE0 }, ms);
            return new byte[][] { hs, all };
        } finally {
            // A read left pending after a timeout makes Dispose block; cancel it first.
            // 逾時後還掛著的讀取會讓關檔卡住，先取消再關。
            CancelIoEx(h, IntPtr.Zero);
            try { fs.Dispose(); } catch (Exception) { }
        }
    }
}
'@
if (-not ('MsiPsuHid' -as [type])) { Add-Type -TypeDefinition $src -Language CSharp }

# Linear11: top 5 bits = signed exponent, low 11 bits = signed mantissa; value = mantissa * 2^exponent
function L11([byte[]]$b, [int]$i) {
    $v = [int]$b[$i] -bor ([int]$b[$i + 1] -shl 8)
    $e = $v -shr 11; if ($e -ge 16) { $e -= 32 }
    $m = $v -band 0x7FF; if ($m -ge 1024) { $m -= 2048 }
    return [math]::Round($m * [math]::Pow(2, $e), 3)
}

$out = [ordered]@{ ok = $false; pid = ('{0:X4}' -f $ProductId); at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
try {
    $res = [MsiPsuHid]::Query(0x0DB0, $ProductId, 2000)
    $r = $res[1]
    # The reply starts with the command echo 51 E0, possibly preceded by the report ID; locate the echo.
    $base = -1
    foreach ($k in 0, 1) { if ($r[$k] -eq 0x51 -and $r[$k + 1] -eq 0xE0) { $base = $k; break } }
    if ($base -lt 0) {
        if ($r[1] -eq 0xFE -or $r[2] -eq 0xFE) { throw 'PSU rejected the read command' }
        throw ('reply does not start with 51 E0: ' + (($r[0..7] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
    }
    $d = $base   # offsets below are relative to the start of the echo
    # Data area (2 bytes after the echo): 12V rails 1-5 as (voltage, current), then 12V total, 5V, 3.3V, ...
    $rails12 = @(); for ($n = 0; $n -lt 5; $n++) { $rails12 += [ordered]@{ v = (L11 $r ($d + 2 + $n * 4)); a = (L11 $r ($d + 4 + $n * 4)) } }
    $watts = L11 $r ($d + 34)
    $eff = L11 $r ($d + 36)
    if ($eff -gt 0 -and $eff -le 1) { $eff = [math]::Round($eff * 100, 2) }   # some firmware may report 0..1
    $out.ok = $true
    $out.watts_out = $watts
    $out.efficiency = $eff
    # Input (wall) power is estimated: output / efficiency. 牆上輸入功率是推算值。
    $out.watts_in = if ($eff -gt 0) { [math]::Round($watts / ($eff / 100), 1) } else { $null }
    $out.temp_c = L11 $r ($d + 38)
    $out.fan_rpm = L11 $r ($d + 40)
    $out.v12_total = [ordered]@{ v = (L11 $r ($d + 22)); a = (L11 $r ($d + 24)) }
    $out.v12_rails = $rails12
    $out.v5 = [ordered]@{ v = (L11 $r ($d + 26)); a = (L11 $r ($d + 28)) }
    $out.v3_3 = [ordered]@{ v = (L11 $r ($d + 30)); a = (L11 $r ($d + 32)) }
    $out.raw = (($r[0..47] | ForEach-Object { '{0:X2}' -f $_ }) -join '')
} catch {
    $out.error = $_.Exception.Message
}
$out | ConvertTo-Json -Compress -Depth 4
