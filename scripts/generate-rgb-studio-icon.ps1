param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\assets\nova-rgb.ico')
)

$ErrorActionPreference = 'Stop'
$base64Path = Join-Path $PSScriptRoot '..\assets\nova-rgb.ico.b64'
if (-not (Test-Path $base64Path)) { throw "Nova RGB icon source missing: $base64Path" }

$encoded = (Get-Content $base64Path -Raw).Trim()
$bytes = [Convert]::FromBase64String($encoded)
$dir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $dir -Force | Out-Null
[IO.File]::WriteAllBytes($OutputPath, $bytes)

$sha = (Get-FileHash $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = 'd3ed802a4ca1cfdbfcf9266638ea7d4128c9257e37319ced6fed58c8ff947d61'
if ($sha -ne $expected) { throw "Nova RGB icon hash mismatch. Expected $expected, got $sha" }

Write-Host "Nova RGB icon ready: $OutputPath"
Write-Host "SHA256=$sha"
