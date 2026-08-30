$ErrorActionPreference = 'Stop'

$root = Join-Path $env:RUNNER_TEMP 'mkminipro-inspect'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Path $root | Out-Null

Write-Host 'Downloading official Mars Gaming MKMINIPRO package...'
$zip = Join-Path $root 'mkminipro.zip'
Invoke-WebRequest -Uri 'https://marsgaming.eu/en/index.php?controller=attachment&id_attachment=863' -OutFile $zip -UseBasicParsing
Write-Host ('Package SHA256: ' + (Get-FileHash $zip -Algorithm SHA256).Hash)

$package = Join-Path $root 'package'
Expand-Archive -Path $zip -DestinationPath $package -Force
$installer = Get-ChildItem $package -Recurse -File -Filter *.exe | Sort-Object Length -Descending | Select-Object -First 1
if (-not $installer) { throw 'Installer not found in official package.' }
Write-Host ('Installer: ' + $installer.FullName)

Write-Host 'Downloading innoextract 1.9...'
$toolZip = Join-Path $root 'innoextract.zip'
Invoke-WebRequest -Uri 'https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip' -OutFile $toolZip -UseBasicParsing
$toolDir = Join-Path $root 'innoextract'
Expand-Archive -Path $toolZip -DestinationPath $toolDir -Force
$inno = Get-ChildItem $toolDir -Recurse -File -Filter innoextract.exe | Select-Object -First 1
if (-not $inno) { throw 'innoextract.exe not found.' }

# Static extraction only: the vendor installer is NEVER launched.
$out = Join-Path $root 'extracted'
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $out
& $inno.FullName --extract --silent $installer.FullName
$exit = $LASTEXITCODE
Pop-Location
if ($exit -ne 0) { throw "innoextract failed: $exit" }

$report = Join-Path $root 'keymap-report.txt'
'MKMINIPRO KEYMAP STATIC INSPECTION' | Set-Content $report -Encoding UTF8
('Generated: ' + (Get-Date -Format o)) | Add-Content $report
'' | Add-Content $report
'=== FILE LIST ===' | Add-Content $report
Get-ChildItem $out -Recurse -File | Sort-Object FullName | ForEach-Object {
    ('{0}`t{1}' -f $_.Length,$_.FullName) | Add-Content $report
}

'' | Add-Content $report
'=== SMALL TEXT CONFIGS (full content) ===' | Add-Content $report
$textExt = @('.ini','.xml','.json','.txt','.cfg','.config','.dat','.csv')
Get-ChildItem $out -Recurse -File | Where-Object { $textExt -contains $_.Extension.ToLowerInvariant() -and $_.Length -lt 1048576 } | ForEach-Object {
    ('--- FILE: ' + $_.FullName + ' ---') | Add-Content $report
    try { Get-Content $_.FullName -Raw -ErrorAction Stop | Add-Content $report } catch { ('[unreadable text: ' + $_.Exception.Message + ']') | Add-Content $report }
    '' | Add-Content $report
}

'' | Add-Content $report
'=== KEY / LED / LAYOUT MATCHES ===' | Add-Content $report
$patterns = 'key|led|rgb|index|layout|61K|62K|63K|64K|5566|0008|code|row|column|position|light'
Get-ChildItem $out -Recurse -File | Where-Object { $textExt -contains $_.Extension.ToLowerInvariant() } | ForEach-Object {
    $hits = Select-String -Path $_.FullName -Pattern $patterns -CaseSensitive:$false -ErrorAction SilentlyContinue
    if ($hits) {
        ('--- MATCHES: ' + $_.FullName + ' ---') | Add-Content $report
        $hits | ForEach-Object { ('L{0}: {1}' -f $_.LineNumber,$_.Line) | Add-Content $report }
    }
}

Write-Host '=== REPORT START ==='
Get-Content $report
Write-Host '=== REPORT END ==='

# Copy outputs to workspace so artifact upload has a stable path.
$dest = Join-Path $env:GITHUB_WORKSPACE 'inspection-output'
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item $report (Join-Path $dest 'keymap-report.txt')
Copy-Item $out (Join-Path $dest 'extracted') -Recurse
