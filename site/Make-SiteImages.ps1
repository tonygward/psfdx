# Makes site/src/og-image.png (the social sharing card) and site/src/favicon.png from the ORIGINAL logo.
# The logo itself is only scaled and placed, never redrawn. Needs Windows PowerShell or PowerShell 7 on Windows
# (System.Drawing). The two PNGs are committed, so you only run this if you change the card.
#
#   pwsh ./site/Make-SiteImages.ps1
[CmdletBinding()]
Param()
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$logoPath = Join-Path (Join-Path $root 'images') 'psfdx-logo.png'
$outDir = Join-Path (Join-Path $root 'site') 'src'
$logo = [System.Drawing.Image]::FromFile($logoPath)

function New-Graphics([System.Drawing.Bitmap] $bitmap) {
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    return $g
}

# Social card, 1200 x 630
$card = New-Object System.Drawing.Bitmap -ArgumentList 1200, 630
$g = New-Graphics $card
$rect = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, 1200, 630
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList $rect, ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), 60
$g.FillRectangle($bg, $rect)
$bar = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 7, 196, 193))
$g.FillRectangle($bar, 0, 614, 1200, 16)

$logoWidth = 840
$logoHeight = [int]($logo.Height * $logoWidth / $logo.Width)
$g.DrawImage($logo, [int]((1200 - $logoWidth) / 2), 70, $logoWidth, $logoHeight)

$navy = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 19, 64, 108))
$teal = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 0, 111, 108))
$centre = New-Object System.Drawing.StringFormat
$centre.Alignment = 'Center'
$headline = New-Object System.Drawing.Font -ArgumentList 'Segoe UI Semibold', 58, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$sub = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 30, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Salesforce. Meet PowerShell.', $headline, $navy, (New-Object System.Drawing.RectangleF -ArgumentList 0, 350, 1200, 80), $centre)
$g.DrawString('Powerful Salesforce tools. Familiar PowerShell commands.', $sub, $teal, (New-Object System.Drawing.RectangleF -ArgumentList 0, 440, 1200, 50), $centre)
$g.DrawString('Install-Module psfdx', (New-Object System.Drawing.Font -ArgumentList 'Consolas', 30, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)), $navy, (New-Object System.Drawing.RectangleF -ArgumentList 0, 520, 1200, 50), $centre)
$g.Dispose()
$card.Save((Join-Path $outDir 'og-image.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$card.Dispose()

# Favicon: the cloud mark at the left of the logo, cropped square and scaled to 64 x 64
$icon = New-Object System.Drawing.Bitmap -ArgumentList 64, 64
$g = New-Graphics $icon
$source = New-Object System.Drawing.Rectangle -ArgumentList 30, 54, 112, 112
$g.DrawImage($logo, (New-Object System.Drawing.Rectangle -ArgumentList 0, 0, 64, 64), $source, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$icon.Save((Join-Path $outDir 'favicon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$icon.Dispose()
$logo.Dispose()
"Wrote og-image.png and favicon.png to $outDir"
