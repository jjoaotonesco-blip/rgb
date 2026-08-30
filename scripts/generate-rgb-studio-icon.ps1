param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\assets\rgb-studio.ico')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
'@

$size = 256
$bmp = New-Object Drawing.Bitmap $size, $size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([Drawing.Color]::Transparent)

function RoundedPath([Drawing.RectangleF]$r, [float]$radius) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Dark rounded app tile.
$outer = New-Object Drawing.RectangleF 12,12,232,232
$outerPath = RoundedPath $outer 42
$bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $outer, ([Drawing.Color]::FromArgb(255,10,13,24)), ([Drawing.Color]::FromArgb(255,24,13,35)), 45
$g.FillPath($bgBrush, $outerPath)

# RGB neon outline.
$grad = New-Object Drawing.Drawing2D.LinearGradientBrush $outer, ([Drawing.Color]::FromArgb(255,0,220,255)), ([Drawing.Color]::FromArgb(255,255,35,150)), 20
$pen = New-Object Drawing.Pen $grad, 7
$g.DrawPath($pen, $outerPath)

# Timeline / orbit arc.
$arcRect = New-Object Drawing.RectangleF 39,32,178,176
$arcPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(220,80,210,255)), 7
$arcPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
$arcPen.EndCap = [Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($arcPen, $arcRect, 205, 245)
$arcPen.Color = [Drawing.Color]::FromArgb(230,255,45,175)
$g.DrawArc($arcPen, $arcRect, 305, 90)

# Keyboard body.
$kb = New-Object Drawing.RectangleF 53,78,150,91
$kbPath = RoundedPath $kb 16
$kbFill = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(245,11,15,25))
$g.FillPath($kbFill, $kbPath)
$kbOutline = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(220,120,135,170)), 3
$g.DrawPath($kbOutline, $kbPath)

$colors = @(
    [Drawing.Color]::FromArgb(255,0,210,255),
    [Drawing.Color]::FromArgb(255,85,90,255),
    [Drawing.Color]::FromArgb(255,190,50,255),
    [Drawing.Color]::FromArgb(255,255,40,145),
    [Drawing.Color]::FromArgb(255,255,105,45),
    [Drawing.Color]::FromArgb(255,120,255,45)
)

# Key rows.
$keyW = 20; $keyH = 20; $gap = 5
for ($row = 0; $row -lt 3; $row++) {
    $count = if ($row -eq 2) { 5 } else { 6 }
    $startX = if ($row -eq 2) { 64 } else { 62 }
    for ($col = 0; $col -lt $count; $col++) {
        $x = $startX + $col * ($keyW + $gap)
        $y = 88 + $row * 25
        $w = if ($row -eq 2 -and $col -eq 2) { 45 } else { $keyW }
        if ($row -eq 2 -and $col -gt 2) { $x += 25 }
        $r = New-Object Drawing.RectangleF $x,$y,$w,$keyH
        $path = RoundedPath $r 5
        $c = $colors[($col + $row) % $colors.Count]
        $shadow = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(95,$c.R,$c.G,$c.B)), 7
        $g.DrawPath($shadow,$path)
        $fill = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255,18,24,38))
        $g.FillPath($fill,$path)
        $kp = New-Object Drawing.Pen $c, 2
        $g.DrawPath($kp,$path)
        $shadow.Dispose(); $fill.Dispose(); $kp.Dispose(); $path.Dispose()
    }
}

# Timeline line and RGB keyframes.
$linePen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(180,115,125,160)), 3
$g.DrawLine($linePen, 62,193,194,193)
$dotColors = @(
    [Drawing.Color]::FromArgb(255,0,220,255),
    [Drawing.Color]::FromArgb(255,150,65,255),
    [Drawing.Color]::FromArgb(255,255,65,170),
    [Drawing.Color]::FromArgb(255,255,165,45),
    [Drawing.Color]::FromArgb(255,70,255,85)
)
for ($i=0; $i -lt $dotColors.Count; $i++) {
    $x = 66 + $i * 31
    $glow = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(80,$dotColors[$i].R,$dotColors[$i].G,$dotColors[$i].B))
    $solid = New-Object Drawing.SolidBrush $dotColors[$i]
    $g.FillEllipse($glow,$x-9,184,18,18)
    $g.FillEllipse($solid,$x-5,188,10,10)
    $glow.Dispose(); $solid.Dispose()
}

# White playhead dot on the orbit.
$whiteGlow = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(100,255,255,255))
$white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
$g.FillEllipse($whiteGlow,190,55,24,24)
$g.FillEllipse($white,196,61,12,12)

$dir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$handle = $bmp.GetHicon()
try {
    $icon = [Drawing.Icon]::FromHandle($handle)
    $fs = [IO.File]::Create($OutputPath)
    try { $icon.Save($fs) } finally { $fs.Dispose(); $icon.Dispose() }
} finally {
    [NativeIcon]::DestroyIcon($handle) | Out-Null
}

$preview = [IO.Path]::ChangeExtension($OutputPath, '.png')
$bmp.Save($preview, [Drawing.Imaging.ImageFormat]::Png)

$whiteGlow.Dispose(); $white.Dispose(); $linePen.Dispose(); $kbOutline.Dispose(); $kbFill.Dispose()
$arcPen.Dispose(); $pen.Dispose(); $grad.Dispose(); $bgBrush.Dispose(); $outerPath.Dispose(); $kbPath.Dispose()
$g.Dispose(); $bmp.Dispose()
Write-Host "Generated icon: $OutputPath"
