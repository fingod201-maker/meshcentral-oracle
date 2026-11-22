Add-Type -AssemblyName System.Drawing

$out = "meshcentral-oracle\mh1\mc-assets"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# --- 450x66 wordmark -------------------------------------------------------
$w = 450; $h = 66
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Transparent)

$mark = New-RoundedPath 0 6 54 54 11
$clay = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(184, 92, 46))
$g.FillPath($clay, $mark)

$paper = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(247, 244, 238))
$rsFont = New-Object System.Drawing.Font('Arial', 22, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString('RS', $rsFont, $paper, (New-Object System.Drawing.RectangleF(0, 6, 54, 54)), $sf)

$nameFont = New-Object System.Drawing.Font('Arial', 21, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('REYES SITEWORK', $nameFont, $paper, 68, 9)

$sand = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(233, 160, 110))
$subFont = New-Object System.Drawing.Font('Arial', 8.5, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('S E C U R E   D E V I C E   P O R T A L', $subFont, $sand, 69, 40)

$bmp.Save("$out\reyes-title.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# --- background helper -----------------------------------------------------
function Save-CoverJpeg([string]$srcPath, [string]$dstPath, [int]$ow, [int]$oh, [int]$topAlpha, [int]$bottomAlpha, [long]$quality) {
    $src = [System.Drawing.Image]::FromFile($srcPath)
    $bmp = New-Object System.Drawing.Bitmap($ow, $oh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $scale = [Math]::Max($ow / $src.Width, $oh / $src.Height)
    $dw = [int][Math]::Ceiling($src.Width * $scale)
    $dh = [int][Math]::Ceiling($src.Height * $scale)
    $dx = [int](($ow - $dw) / 2)
    $dy = [int](($oh - $dh) / 2)
    $g.DrawImage($src, $dx, $dy, $dw, $dh)

    $rect = New-Object System.Drawing.Rectangle(0, 0, $ow, $oh)
    $vertical = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb($topAlpha, 8, 15, 20),
        [System.Drawing.Color]::FromArgb($bottomAlpha, 8, 15, 20),
        90)
    $g.FillRectangle($vertical, $rect)

    $horizontal = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(95, 8, 15, 20),
        [System.Drawing.Color]::FromArgb(0, 8, 15, 20),
        0)
    $g.FillRectangle($horizontal, $rect)

    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, $quality)
    $bmp.Save($dstPath, $codec, $ep)

    $g.Dispose(); $bmp.Dispose(); $src.Dispose()
}

Save-CoverJpeg "meshcentral-oracle\mh1\site\img\hero.jpg" "$out\login-bg.jpg" 1920 1080 110 220 82
Save-CoverJpeg "meshcentral-oracle\mh1\site\img\driveway-finished.jpg" "$out\welcome-bg.jpg" 1920 1080 120 200 82

# --- 303x303 touch icon ----------------------------------------------------
$size = 303
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::FromArgb(16, 28, 36))
$font = New-Object System.Drawing.Font('Arial', 118, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString('RS', $font, $paper, (New-Object System.Drawing.RectangleF(0, 0, $size, $size)), $sf)
$bmp.Save("$out\favicon-303x303.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

Get-ChildItem $out | Select-Object Name, @{N='KB';E={[math]::Round($_.Length/1KB)}}
