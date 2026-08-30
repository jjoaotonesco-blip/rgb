$ErrorActionPreference = 'Stop'

$root = Join-Path $env:RUNNER_TEMP 'mkminipro-keymap'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Path $root | Out-Null

$zip = Join-Path $root 'mkminipro.zip'
Invoke-WebRequest -Uri 'https://marsgaming.eu/en/index.php?controller=attachment&id_attachment=863' -OutFile $zip -UseBasicParsing
$pkg = Join-Path $root 'pkg'
Expand-Archive $zip $pkg -Force
$installer = Get-ChildItem $pkg -Recurse -File -Filter *.exe | Sort-Object Length -Descending | Select-Object -First 1
if (-not $installer) { throw 'Installer not found' }

$toolZip = Join-Path $root 'inno.zip'
Invoke-WebRequest -Uri 'https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip' -OutFile $toolZip -UseBasicParsing
$tools = Join-Path $root 'tools'
Expand-Archive $toolZip $tools -Force
$inno = Get-ChildItem $tools -Recurse -File -Filter innoextract.exe | Select-Object -First 1
if (-not $inno) { throw 'innoextract missing' }

$out = Join-Path $root 'out'
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $out
& $inno.FullName --extract --silent $installer.FullName
if ($LASTEXITCODE -ne 0) { throw "innoextract failed $LASTEXITCODE" }
Pop-Location

Write-Host '=== LIKELY LAYOUT FILES ==='
Get-ChildItem $out -Recurse -File | Where-Object {
    $_.Name -match '(?i)(key|layout|61k|62k|63k|64k|rgb|led)' -or $_.Extension -match '(?i)\.xml|\.ini|\.json|\.cfg|\.dat'
} | Sort-Object FullName | ForEach-Object { Write-Host ($_.FullName.Substring($out.Length + 1)) }

Write-Host '=== CONCISE KEYMAP CANDIDATES ==='
$files = Get-ChildItem $out -Recurse -File | Where-Object { $_.Extension -match '(?i)\.xml|\.ini|\.json|\.cfg|\.txt|\.dat|\.csv' -and $_.Length -lt 2MB }
foreach ($f in $files) {
    $lines = Select-String -Path $f.FullName -Pattern '(?i)(key_rgb|key_code|led.?index|rgb.?index|light.?index|key.?index|<key|keyname|key_name|keyboard|layout|\bC\b|\bX\b|\bV\b)' -ErrorAction SilentlyContinue
    if ($lines) {
        Write-Host ('--- ' + $f.FullName.Substring($out.Length + 1) + ' ---')
        $lines | Select-Object -First 220 | ForEach-Object { Write-Host ('L{0}: {1}' -f $_.LineNumber, $_.Line.Trim()) }
    }
}

Write-Host '=== XML ATTRIBUTE WALK ==='
Get-ChildItem $out -Recurse -File -Filter *.xml | ForEach-Object {
    try {
        [xml]$xml = Get-Content $_.FullName -Raw
        $nodes = $xml.SelectNodes('//*')
        $printed = 0
        foreach ($n in $nodes) {
            if (-not $n.Attributes) { continue }
            $pairs = @()
            foreach ($a in $n.Attributes) {
                if ($a.Name -match '(?i)(key|led|rgb|index|code|name|x|y|row|col|width|height|pos|light)') {
                    $pairs += ($a.Name + '=' + $a.Value)
                }
            }
            $joined = $pairs -join ' '
            if ($pairs.Count -ge 2 -and $joined -match '(?i)(key|led|rgb|index|code|name)') {
                if ($printed -eq 0) { Write-Host ('--- XML ' + $_.FullName.Substring($out.Length + 1) + ' ---') }
                Write-Host ($n.Name + ' ' + $joined)
                $printed++
                if ($printed -ge 180) { break }
            }
        }
    } catch { }
}

Write-Host '=== RAW SMALL XML/INI WITH 64K/KEY_RGB ==='
foreach ($f in $files) {
    $raw = $null
    try { $raw = Get-Content $f.FullName -Raw } catch { continue }
    if ($raw -match '(?i)(64K|key_rgb|key_code)') {
        Write-Host ('--- RAW ' + $f.FullName.Substring($out.Length + 1) + ' ---')
        if ($raw.Length -gt 40000) { $raw = $raw.Substring(0,40000) }
        Write-Host $raw
    }
}
