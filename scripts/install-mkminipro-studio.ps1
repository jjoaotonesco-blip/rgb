param(
    [Parameter(Mandatory=$true)][string]$PublishDir
)

$ErrorActionPreference = 'Stop'

$docs = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($docs) -or $docs -match '(?i)systemprofile') {
    $docs = Join-Path $env:USERPROFILE 'Documents'
}
if (-not (Test-Path $docs)) { New-Item -ItemType Directory -Path $docs -Force | Out-Null }

$root = Join-Path $docs 'MKMINIPRO Studio'
$appDir = Join-Path $root 'App'
$projectDir = Join-Path $root 'Project'

Write-Host "Installing to: $root"

# Close only our own previous build so files can be replaced. Never kill the vendor software here.
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'MKMINIPRO Studio' } | Stop-Process -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $appDir -Force | Out-Null
Get-ChildItem $appDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $PublishDir '*') $appDir -Recurse -Force

$exe = Join-Path $appDir 'MKMINIPRO Studio.exe'
if (-not (Test-Path $exe)) { throw "Published EXE not found: $exe" }

# Keep a local editable/project snapshot in Documents as requested.
if (Test-Path $projectDir) { Remove-Item $projectDir -Recurse -Force }
New-Item -ItemType Directory -Path $projectDir | Out-Null
$sourceItems = @('src','scripts','.github','README.md')
foreach ($item in $sourceItems) {
    $from = Join-Path $env:GITHUB_WORKSPACE $item
    if (Test-Path $from) { Copy-Item $from $projectDir -Recurse -Force }
}

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
if (-not (Test-Path $desktop)) { New-Item -ItemType Directory -Path $desktop -Force | Out-Null }
$shortcutPath = Join-Path $desktop 'MKMINIPRO Studio.lnk'
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = $appDir
$shortcut.Description = 'MKMINIPRO RGB presets, static editor and animation timeline'
$shortcut.Save()

@(
    'MKMINIPRO Studio installed successfully.'
    ('Installed: ' + (Get-Date -Format o))
    ('App: ' + $exe)
    ('Project: ' + $projectDir)
    ('Shortcut: ' + $shortcutPath)
) | Set-Content (Join-Path $root 'install-info.txt') -Encoding UTF8

Write-Host 'INSTALL_OK'
Write-Host "APP=$exe"
Write-Host "PROJECT=$projectDir"
Write-Host "SHORTCUT=$shortcutPath"
