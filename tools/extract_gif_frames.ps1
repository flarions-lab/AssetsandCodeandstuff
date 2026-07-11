# extract_gif_frames.ps1
#
# Converts an animated GIF into a sequence of PNG frames + a manifest.json
# describing frame count, per-frame delays (ms) and source size.
#
# Godot 4 has no built-in animated-GIF player, so HexGifBackgrounds are
# pre-converted into frame sequences at edit time. At runtime,
# BackgroundManager.gd loads the PNG frames + manifest.json for the
# selected background and builds an AnimatedTexture from them.
#
# Usage:
#   pwsh tools/extract_gif_frames.ps1 -GifPath "assets\HexGifBackgrounds\Space Falling GIF by varundo.gif" -OutId "space_falling" -MaxDim 480 -MaxFrames 60
#
# Params:
#   -GifPath    Path to the source .gif
#   -OutId      Output folder name (also used as the background's internal id)
#   -MaxDim     Max width/height in pixels; frames are downscaled (aspect kept) if larger. 0 = no resize.
#   -MaxFrames  Max number of output frames; if the GIF has more, frames are sampled evenly. 0 = no cap.

param(
    [Parameter(Mandatory=$true)][string]$GifPath,
    [Parameter(Mandatory=$true)][string]$OutId,
    [int]$MaxDim = 480,
    [int]$MaxFrames = 60,
    [switch]$Upscale
)

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$gifFull = Resolve-Path $GifPath
$outDir = Join-Path $root "assets\HexGifBackgrounds\frames\$OutId"

if (Test-Path $outDir) {
    Remove-Item -Recurse -Force $outDir
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$img = [System.Drawing.Image]::FromFile($gifFull)
$dim = [System.Drawing.Imaging.FrameDimension]::Time
$totalFrames = $img.GetFrameCount($dim)

# Frame delays are stored in the GIF's PropertyTagFrameDelay (0x5100), units of 10ms, 4 bytes per frame (LE).
$delayProp = $img.GetPropertyItem(0x5100)
$delaysRaw = $delayProp.Value
$allDelaysMs = New-Object int[] $totalFrames
for ($i = 0; $i -lt $totalFrames; $i++) {
    $b = $i * 4
    $hundredths = [BitConverter]::ToInt32($delaysRaw, $b)
    $ms = $hundredths * 10
    if ($ms -le 0) { $ms = 100 }  # GIFs with 0 delay -> default ~10fps
    $allDelaysMs[$i] = $ms
}

# Decide which source frame indices to keep
$indices = @()
if ($MaxFrames -gt 0 -and $totalFrames -gt $MaxFrames) {
    for ($k = 0; $k -lt $MaxFrames; $k++) {
        $idx = [math]::Floor($k * $totalFrames / $MaxFrames)
        $indices += [int]$idx
    }
} else {
    $indices = 0..($totalFrames - 1)
}

# Compute output size. If -Upscale is set, frames smaller than MaxDim are
# scaled UP (with smoothing) to MaxDim as well as scaled down if larger;
# otherwise (default) only downscale when larger than MaxDim.
$srcW = $img.Width
$srcH = $img.Height
$outW = $srcW
$outH = $srcH
$needsResize = ($MaxDim -gt 0) -and (($srcW -gt $MaxDim -or $srcH -gt $MaxDim) -or ($Upscale -and ($srcW -lt $MaxDim -and $srcH -lt $MaxDim)))
if ($needsResize) {
    if ($srcW -ge $srcH) {
        $outW = $MaxDim
        $outH = [math]::Round($srcH * $MaxDim / $srcW)
    } else {
        $outH = $MaxDim
        $outW = [math]::Round($srcW * $MaxDim / $srcH)
    }
}

$manifestDelays = New-Object System.Collections.Generic.List[int]
$frameOut = 0
foreach ($idx in $indices) {
    [void]$img.SelectActiveFrame($dim, $idx)

    $bmp = New-Object System.Drawing.Bitmap($outW, $outH)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Black)
    $g.DrawImage($img, 0, 0, $outW, $outH)
    $g.Dispose()

    $framePath = Join-Path $outDir ("frame_{0:D4}.png" -f $frameOut)
    $bmp.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    # Sum delays of any source frames collapsed into this output frame
    $nextIdx = $totalFrames
    $posInIndices = [array]::IndexOf($indices, $idx)
    if ($posInIndices -lt ($indices.Count - 1)) {
        $nextIdx = $indices[$posInIndices + 1]
    }
    $sum = 0
    for ($s = $idx; $s -lt $nextIdx; $s++) { $sum += $allDelaysMs[$s] }
    if ($sum -le 0) { $sum = $allDelaysMs[$idx] }
    $manifestDelays.Add($sum)

    $frameOut++
}

$img.Dispose()

$manifest = [PSCustomObject]@{
    id          = $OutId
    source      = (Split-Path -Leaf $GifPath)
    frame_count = $frameOut
    width       = $outW
    height      = $outH
    delays_ms   = $manifestDelays
}
$manifestJson = $manifest | ConvertTo-Json -Compress
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $outDir "manifest.json"), $manifestJson, $utf8NoBom)

Write-Host "Wrote $frameOut frames ($outW x $outH) to $outDir"
