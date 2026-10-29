# Decode controlled fixtures using the reader's actual parser; never run Query.
$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\read_msi_psu.ps1'))
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Reader syntax errors' }
$l11 = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'L11' }, $true)
$decode = [regex]::Match($text, '(?s)    \$r = \$res\[1\].*?\r?\n} catch \{')
if (-not $l11 -or -not $decode.Success) { throw 'Parser source not found' }
$body = $decode.Value.Substring(0,$decode.Value.LastIndexOf('} catch {'))
if ($body.Contains('[MsiPsuHid]')) { throw 'Unexpected hardware call in parser' }
$program = 'param([byte[]]$packet)' + "`n" + $l11.Extent.Text + "`n" +
    '$res = @($null,$packet); $out = [ordered]@{ok=$false}; try {' + "`n" + $body +
    '} catch { $out.error=$_.Exception.Message }; $out'
$parser = [scriptblock]::Create($program)
$hex = '0051E001D300F001D30CF001D301F001D30FF001D308F001D320F085CA17E0AEC915E0350890EA1D0000080000000000'
$sample = [byte[]]@(for($i=0;$i -lt $hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)})
$passed = 0
foreach($packet in @($sample,[byte[]]$sample[1..47],[byte[]]$sample[0..42])) {
    $decoded = & $parser $packet
    if (-not $decoded.ok -or $decoded.watts_out -ne 106 -or $decoded.efficiency -ne 82 -or $decoded.temp_c -ne 29 -or $decoded.watts_in -ne 129.3) { throw 'Captured fixture values changed' }
    if ($decoded.raw.Length -ne (2 * $packet.Length)) { throw 'Raw bytes were padded or truncated unexpectedly' }
    $passed++
}
$invalid = & $parser ([byte[]](0,0x51,0xE0))
if ($invalid.ok -or -not $invalid.error) { throw 'Short packet reported success' }
$passed++
[ordered]@{passed=$passed;hardware_access=$false;watts_out=106;efficiency=82;temp_c=29} | ConvertTo-Json -Compress
