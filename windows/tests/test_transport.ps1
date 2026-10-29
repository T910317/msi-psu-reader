# Offline tests: only the inline C# Ask method is called with a fake FileStream.
# No Query, device enumeration, HID API, or PSU command is executed.
$ErrorActionPreference = 'Stop'
$reader = Join-Path $PSScriptRoot '..\read_msi_psu.ps1'
$text = [IO.File]::ReadAllText($reader)
$sourceMatch = [regex]::Match($text, "(?s)\`$src = @'\r?\n(.*?)\r?\n'@")
if (-not $sourceMatch.Success) { throw 'Inline C# not found' }
if ('MsiPsuHid' -as [type]) { throw 'Run tests in a fresh PowerShell process' }
Add-Type -TypeDefinition $sourceMatch.Groups[1].Value -Language CSharp
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

public class MsiPsuReplyStream : FileStream {
    readonly Queue<byte[]> replies;
    readonly bool stall;
    public int Reads;
    public bool Cancelled;
    public byte[] Written;
    public MsiPsuReplyStream(string path, byte[][] data, bool stallRead)
        : base(path, FileMode.Create, FileAccess.ReadWrite) {
        replies = new Queue<byte[]>(data); stall = stallRead;
    }
    public override void Write(byte[] b, int offset, int count) {
        Written = new byte[count]; Array.Copy(b, offset, Written, 0, count);
    }
    public override Task<int> ReadAsync(byte[] b, int offset, int count, CancellationToken token) {
        Reads++;
        if (stall) {
            var pending = new TaskCompletionSource<int>();
            token.Register(() => { Cancelled = true; pending.TrySetCanceled(); });
            return pending.Task;
        }
        if (replies.Count == 0) return Task.FromResult(0);
        var r = replies.Dequeue(); int n = Math.Min(count, r.Length);
        Array.Copy(r, 0, b, offset, n); return Task.FromResult(n);
    }
}
public static class MsiPsuTransportTests {
    static byte[] Hex(string s) {
        var r = new byte[s.Length / 2];
        for (int i=0; i<r.Length; i++) r[i] = Convert.ToByte(s.Substring(i*2,2),16);
        return r;
    }
    static Dictionary<string,object> Check(Type helper, string path, string name, byte[] cmd, byte[][] replies,
        Type expectedError, int expectedBytes, int expectedReads, bool stall) {
        using (var stream = new MsiPsuReplyStream(path, replies, stall)) {
            byte[] result = null; Exception error = null;
            try {
                var method = helper.GetMethod("Ask", BindingFlags.Static | BindingFlags.NonPublic);
                result = (byte[])method.Invoke(null,new object[]{stream,65,65,cmd,stall ? 25 : 1000});
            } catch (TargetInvocationException e) { error = e.InnerException; }
            if (expectedError == null && error != null) throw new Exception(name + ": " + error);
            if (expectedError != null && (error == null || !expectedError.IsInstanceOfType(error)))
                throw new Exception(name + ": expected " + expectedError.Name);
            if (result != null && result.Length != expectedBytes) throw new Exception(name + ": reply length");
            if (stream.Reads != expectedReads) throw new Exception(name + ": read count");
            if (stall && !stream.Cancelled) throw new Exception(name + ": pending read not cancelled");
            if (stream.Written.Length != 65 || stream.Written[0] != 0 || stream.Written[1] != cmd[0] || stream.Written[2] != cmd[1])
                throw new Exception(name + ": report framing");
            return new Dictionary<string,object>{{"test",name},{"passed",true},{"reads",stream.Reads},{"hardware_access",false}};
        }
    }
    public static object[] Run(Type helper, string path) {
        var valid = Hex("0051E001D300F001D30CF001D301F001D30FF001D308F001D320F085CA17E0AEC915E0350890EA1D0000080000000000");
        var noId = new byte[valid.Length-1]; Array.Copy(valid,1,noId,0,noId.Length);
        var read = new byte[]{0x51,0xE0}; var hs = new byte[]{0xFA,0x51};
        var wrong = new byte[]{0,0x51,0xD1};
        return new object[]{
            Check(helper,path,"valid_capture",read,new[]{valid},null,48,1,false),
            Check(helper,path,"without_report_id",read,new[]{noId},null,47,1,false),
            Check(helper,path,"short_read",read,new[]{new byte[]{0,0x51,0xE0}},typeof(IOException),0,1,false),
            Check(helper,path,"read_rejected",read,new[]{new byte[]{0,0x51,0xFE}},typeof(IOException),0,1,false),
            Check(helper,path,"handshake_rejected",hs,new[]{new byte[]{0,0xFA,0xFE}},typeof(IOException),0,1,false),
            Check(helper,path,"handshake_ack",hs,new[]{new byte[]{0,0xFA,0x51}},null,3,1,false),
            Check(helper,path,"seventh_reply",read,new[]{wrong,wrong,wrong,wrong,wrong,wrong,valid},null,48,7,false),
            Check(helper,path,"end_of_stream",read,new byte[0][],typeof(EndOfStreamException),0,1,false),
            Check(helper,path,"timeout_cancels_read",read,new byte[0][],typeof(TimeoutException),0,1,true)
        };
    }
}
'@ -Language CSharp
$probePath = Join-Path ([IO.Path]::GetTempPath()) ('msi-psu-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    $results = [MsiPsuTransportTests]::Run([MsiPsuHid], $probePath)
    [ordered]@{passed=$results.Count;hardware_access=$false;results=$results} | ConvertTo-Json -Depth 5
} finally {
    if (Test-Path -LiteralPath $probePath) { Remove-Item -LiteralPath $probePath }
}
