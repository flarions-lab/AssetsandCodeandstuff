# interpolate_frames.ps1
#
# Doubles the frame count of an already-extracted background by inserting a
# 50%-blended frame between every consecutive pair (wrapping at the end), and
# halves each original frame's delay so the total loop duration is unchanged.
# Useful when a short source GIF (few unique frames) looks choppy/stuttery —
# blended in-between frames make the motion read as smoother without changing
# overall speed.
#
# Usage:
#   pwsh tools/interpolate_frames.ps1 -Id "star_wars_space"
#
# Re-run extract_gif_frames.ps1 first if you want to start over from the
# original source frame count.

param(
    [Parameter(Mandatory=$true)][string]$Id
)

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "assets\HexGifBackgrounds\frames\$Id"
$manifestPath = Join-Path $dir "manifest.json"

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$oldCount = $manifest.frame_count
$oldDelays = $manifest.delays_ms

if (($oldCount * 2) -gt 256) {
    Write-Error "Doubling $oldCount frames would exceed AnimatedTexture's 256-frame limit."
    exit 1
}

# Load all existing frames
$bitmaps = New-Object System.Drawing.Bitmap[] $oldCount
for ($i = 0; $i -lt $oldCount; $i++) {
    $bitmaps[$i] = New-Object System.Drawing.Bitmap((Join-Path $dir ("frame_{0:D4}.png" -f $i)))
}
$w = $bitmaps[0].Width
$h = $bitmaps[0].Height

# Build blended in-between frames: blend(i) = 50/50 of frame i and frame (i+1 wrap)
$newDelays = New-Object System.Collections.Generic.List[int]
$tmpDir = Join-Path $dir "_tmp_interp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$cb = New-Object System.Drawing.Imaging.ColorMatrix
$cb.Matrix33 = 0.5  # alpha scale for the overlay draw

$attr = New-Object System.Drawing.Imaging.ImageAttributes
$attr.SetColorMatrix($cb)

$outIdx = 0
for ($i = 0; $i -lt $oldCount; $i++) {
    # original frame i
    $bitmaps[$i].Save((Join-Path $tmpDir ("frame_{0:D4}.png" -f $outIdx)), [System.Drawing.Imaging.ImageFormat]::Png)
    $newDelays.Add([math]::Round($oldDelays[$i] / 2))
    $outIdx++

    # blended frame between i and (i+1 wrap)
    $next = ($i + 1) % $oldCount
    $blend = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($blend)
    $g.DrawImage($bitmaps[$i], 0, 0, $w, $h)
    $g.DrawImage($bitmaps[$next], (New-Object System.Drawing.Rectangle(0,0,$w,$h)), 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $g.Dispose()
    $blend.Save((Join-Path $tmpDir ("frame_{0:D4}.png" -f $outIdx)), [System.Drawing.Imaging.ImageFormat]::Png)
    $blend.Dispose()
    $newDelays.Add([math]::Round($oldDelays[$i] / 2))
    $outIdx++
}

foreach ($b in $bitmaps) { $b.Dispose() }

# Replace old frames with new sequence
Get-ChildItem -Path $dir -Filter "frame_*.png" | Remove-Item -Force
Get-ChildItem -Path $tmpDir -Filter "*.png" | ForEach-Object {
    Move-Item $_.FullName (Join-Path $dir $_.Name) -Force
}
Remove-Item -Recurse -Force $tmpDir

$newManifest = [PSCustomObject]@{
    id          = $manifest.id
    source      = $manifest.source
    frame_count = $outIdx
    width       = $w
    height      = $h
    delays_ms   = $newDelays
}
$json = $newManifest | ConvertTo-Json -Compress
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($manifestPath, $json, $utf8NoBom)

Write-Host "Interpolated $oldCount -> $outIdx frames for '$Id'"
