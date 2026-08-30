param(
    [Parameter(Mandatory=$true)][string]$OutputIco,
    [string]$OutputPng
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap $size,$size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::FromArgb(10,12,20))

$rect = New-Object System.Drawing.Rectangle 10,10,236,236
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 42
$path.AddArc($rect.X,$rect.Y,$r,$r,180,90)
$path.AddArc($rect.Right-$r,$rect.Y,$r,$r,270,90)
$path.AddArc($rect.Right-$r,$rect.Bottom-$r,$r,$r,0,90)
$path.AddArc($rect.X,$rect.Bottom-$r,$r,$r,90,90)
$path.CloseFigure()

$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,[System.Drawing.Color]::FromArgb(20,28,48),[System.Drawing.Color]::FromArgb(31,12,47),45)
$g.FillPath($bgBrush,$path)

$borderBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,[System.Drawing.Color]::FromArgb(0,220,255),[System.Drawing.Color]::FromArgb(255,30,160),25)
$borderPen = New-Object System.Drawing.Pen($borderBrush,6)
$g.DrawPath($borderPen,$path)

# Abstract RGB 'N' mark only; no words/letters are rendered as text.
$markPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$markPath.AddLine(65,178,65,76)
$markPath.AddLine(65,76,125,155)
$markPath.AddLine(125,155,191,70)
$markPath.AddLine(191,70,191,178)
$markBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle 55,65,145,120),[System.Drawing.Color]::FromArgb(0,220,255),[System.Drawing.Color]::FromArgb(255,20,145),25)
$markPen = New-Object System.Drawing.Pen($markBrush,23)
$markPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$markPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$markPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawPath($markPen,$markPath)

$glowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80,255,255,255),4)
$g.DrawPath($glowPen,$markPath)

if ($OutputPng) {
    $dir = Split-Path -Parent $OutputPng
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($OutputPng,[System.Drawing.Imaging.ImageFormat]::Png)
}

$icoDir = Split-Path -Parent $OutputIco
if ($icoDir) { New-Item -ItemType Directory -Path $icoDir -Force | Out-Null }
$hIcon = $bmp.GetHicon()
try {
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $fs = [System.IO.File]::Create($OutputIco)
    try { $icon.Save($fs) } finally { $fs.Dispose(); $icon.Dispose() }
}
finally {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeIconCleanup {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool DestroyIcon(IntPtr hIcon);
}
'@ -ErrorAction SilentlyContinue
    [NativeIconCleanup]::DestroyIcon($hIcon) | Out-Null
}

$markPen.Dispose(); $markBrush.Dispose(); $borderPen.Dispose(); $borderBrush.Dispose(); $bgBrush.Dispose(); $path.Dispose(); $markPath.Dispose(); $glowPen.Dispose(); $g.Dispose(); $bmp.Dispose()
Write-Host "ICON_OK=$OutputIco"
