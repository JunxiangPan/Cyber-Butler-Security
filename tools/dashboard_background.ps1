#Requires -Version 5.1
<#
Cyber-Butler dashboard background engine (layered rendering).

The window is composed of three layers:

    BackgroundLayer  Grid, IsHitTestVisible = False
      +- Image            png / jpg / bmp, or the first frame of a gif
      +- Image + timer    animated gif (frames decoded by GDI+)
      +- MediaElement     mp4 / webm, muted, looping
    BackgroundOverlay Border with the theme wash, keeps text readable
    RootGrid          the actual dashboard content

Nothing is loaded from NuGet. Animated GIFs are decoded with System.Drawing,
which composites frames (offsets, transparency, disposal) exactly like a GIF
viewer; a DispatcherTimer swaps the frozen BitmapSources. Videos use the
built-in Windows Media Foundation pipeline behind MediaElement.

Written for PowerShell 5.1 / .NET Framework 4.8 (the dashboard host).
#>

Add-Type -AssemblyName PresentationFramework
try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch { }

$script:BgLimits = @{
    ImageBytes     = 64MB
    GifBytes       = 96MB
    VideoBytes     = 256MB
    GifFrames      = 400
    GifPixels      = (16 * 1000 * 1000)
    GifWorkPixels  = (120 * 1024 * 1024)
    GifWidth       = 1280
    GifBudgetBytes = (128 * 1024 * 1024)
}

$script:BgState = @{
    Kind            = 'none'
    Path            = ''
    Animated        = $false
    Frames          = @()
    Delays          = @()
    Index           = 0
    Timer           = $null
    Media           = $null
    Image           = $null
    Settings        = $null
    Width           = 0
    Height          = 0
    Warning         = ''
    PendingWarning  = ''
    PendingPath     = ''
    PendingGen      = 0
    Generation      = 0
    MediaStarted    = $false
    TranscodeTried  = $false
    Transcoded      = ''
    LastMediaError  = ''
}

$script:BgGifState = @{ Image = $null; Stream = $null }
$script:BgStartTimer = $null
$script:BgStartHandler = $null
$script:BgCleanupBound = $false
$script:BgInteractive = $false
$script:BgCommitted = $false
$script:BgSuppressRestart = $false
$script:BgFFmpeg = $null
$script:BgFFmpegResolved = $false

function Write-BgLog([string]$Message) {
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'CyberButler'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $log = Join-Path $dir 'background.log'
        if ((Test-Path -LiteralPath $log) -and ((Get-Item -LiteralPath $log).Length -gt 512KB)) {
            Move-Item -LiteralPath $log -Destination ($log + '.1') -Force -ErrorAction SilentlyContinue
        }
        Add-Content -LiteralPath $log -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

function Get-BgKind([string]$Path) {
    if (-not $Path) { return 'none' }
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.png' { return 'image' }
        '.jpg' { return 'image' }
        '.jpeg' { return 'image' }
        '.bmp' { return 'image' }
        '.gif' { return 'gif' }
        '.mp4' { return 'video' }
        '.webm' { return 'video' }
        default { return 'unsupported' }
    }
}

function Get-BgFileHeader([string]$Path, [int]$Count = 64) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $Count)
        if ($read -lt 1) { return (New-Object byte[] 0) }
        if ($read -lt $Count) {
            $trimmed = New-Object byte[] $read
            [Array]::Copy($buffer, $trimmed, $read)
            return $trimmed
        }
        return $buffer
    } finally {
        $stream.Dispose()
    }
}

function Test-BgMagic([string]$Path, [string]$Kind) {
    $header = Get-BgFileHeader $Path 64
    if ($header.Length -lt 4) { return $false }
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()

    switch ($Kind) {
        'image' {
            if ($extension -eq '.png') {
                return ($header[0] -eq 0x89 -and $header[1] -eq 0x50 -and $header[2] -eq 0x4E -and $header[3] -eq 0x47)
            }
            if ($extension -eq '.jpg' -or $extension -eq '.jpeg') {
                return ($header[0] -eq 0xFF -and $header[1] -eq 0xD8 -and $header[2] -eq 0xFF)
            }
            if ($extension -eq '.bmp') {
                return ($header[0] -eq 0x42 -and $header[1] -eq 0x4D)
            }
            return $false
        }
        'gif' {
            $asText = [Text.Encoding]::ASCII.GetString($header)
            return ($asText.StartsWith('GIF87a') -or $asText.StartsWith('GIF89a'))
        }
        'video' {
            if ($extension -eq '.webm') {
                return ($header[0] -eq 0x1A -and $header[1] -eq 0x45 -and $header[2] -eq 0xDF -and $header[3] -eq 0xA3)
            }
            $asText = [Text.Encoding]::ASCII.GetString($header)
            if ($asText.IndexOf('ftyp') -ge 0) { return $true }
            $atom = if ($header.Length -ge 8) { $asText.Substring(4, 4) } else { '' }
            return ($atom -in @('moov', 'mdat', 'free', 'skip', 'wide', 'styp'))
        }
        default { return $false }
    }
}

function Test-BgFile([string]$Path) {
    $result = [pscustomobject]@{ Ok = $false; Kind = 'none'; Reason = ''; SizeBytes = 0 }
    if (-not $Path) {
        $result.Reason = '未选择文件'
        return $result
    }

    $kind = Get-BgKind $Path
    $result.Kind = $kind
    if ($kind -eq 'unsupported') {
        $result.Reason = '不支持的格式（仅支持 png / jpg / bmp / gif / mp4 / webm）'
        return $result
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $result.Reason = '文件不存在'
        return $result
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    } catch {
        $result.Reason = '文件无法读取'
        return $result
    }
    $result.SizeBytes = $item.Length
    if ($item.Length -lt 16) {
        $result.Reason = '文件损坏或为空'
        return $result
    }

    $limit = switch ($kind) {
        'image' { $script:BgLimits.ImageBytes }
        'gif' { $script:BgLimits.GifBytes }
        'video' { $script:BgLimits.VideoBytes }
        default { 0 }
    }
    if ($limit -gt 0 -and $item.Length -gt $limit) {
        $result.Reason = ('文件过大（{0:N1} MB，上限 {1:N0} MB）' -f ($item.Length / 1MB), ($limit / 1MB))
        return $result
    }

    if (-not (Test-BgMagic $Path $kind)) {
        $result.Reason = '文件损坏，或扩展名与实际格式不匹配'
        return $result
    }

    $result.Ok = $true
    return $result
}

function Clear-BgLayer {
    if (-not $backgroundLayer) { return }
    try {
        if ($backgroundLayer -is [Windows.Controls.Panel]) {
            $backgroundLayer.Children.Clear()
        } elseif ($backgroundLayer -is [Windows.Controls.ContentControl]) {
            $backgroundLayer.Content = $null
        } elseif ($backgroundLayer -is [Windows.Controls.Decorator]) {
            $backgroundLayer.Child = $null
        }
    } catch { }
}

function Set-BgVisual($Element) {
    Clear-BgLayer
    if (-not $Element -or -not $backgroundLayer) { return }
    try {
        if ($backgroundLayer -is [Windows.Controls.Panel]) {
            [void]$backgroundLayer.Children.Add($Element)
        } elseif ($backgroundLayer -is [Windows.Controls.ContentControl]) {
            $backgroundLayer.Content = $Element
        } elseif ($backgroundLayer -is [Windows.Controls.Decorator]) {
            $backgroundLayer.Background = $null
            $backgroundLayer.Child = $Element
        }
    } catch { }
}

function Set-BgOverlay([bool]$Visible) {
    if (-not $backgroundOverlay) { return }
    try { $backgroundOverlay.Visibility = if ($Visible) { 'Visible' } else { 'Collapsed' } } catch { }
}

function Set-BgSolid {
    $state = $script:BgState
    $state.Kind = 'none'
    $state.Path = ''
    $state.Animated = $false
    $state.Width = 0
    $state.Height = 0
    $state.Frames = @()
    $state.Delays = @()
    $state.Index = 0
    $state.Image = $null
    $state.Transcoded = ''
    Clear-BgLayer
    Set-BgOverlay $false
}

function Stop-BgMedia {
    $state = $script:BgState
    $state.Generation = [int]$state.Generation + 1
    $state.PendingGen = 0
    $state.PendingPath = ''
    $state.MediaStarted = $false

    if ($script:BgStartTimer) {
        try { $script:BgStartTimer.Stop() } catch { }
        $script:BgStartTimer = $null
    }
    if ($state.Timer) {
        try { $state.Timer.Stop() } catch { }
        $state.Timer = $null
    }

    if ($state.Media) {
        $media = $state.Media
        $state.Media = $null
        try { $media.Stop() } catch { }
        try { $media.Close() } catch { }
        try { $media.Source = $null } catch { }
        try { $media.Visibility = 'Collapsed' } catch { }
    }

    if ($script:BgGifState.Image) {
        try { $script:BgGifState.Image.Dispose() } catch { }
        $script:BgGifState.Image = $null
    }
    if ($script:BgGifState.Stream) {
        try { $script:BgGifState.Stream.Dispose() } catch { }
        $script:BgGifState.Stream = $null
    }

    $state.Frames = @()
    $state.Delays = @()
    $state.Index = 0
    $state.Image = $null
    $state.TranscodeTried = $false
    $state.Kind = 'none'
    $state.Path = ''
    $state.Animated = $false
    Clear-BgLayer
}

function Resize-BgBitmap($Source, [int]$Width, [int]$Height) {
    if ($Width -lt 1 -or $Height -lt 1) { return $Source }
    $scaled = New-Object Windows.Media.Imaging.TransformedBitmap
    $scaled.BeginInit()
    $scaled.Source = $Source
    $scaled.Transform = New-Object Windows.Media.ScaleTransform -ArgumentList @(
        ([double]$Width / $Source.PixelWidth),
        ([double]$Height / $Source.PixelHeight)
    )
    $scaled.EndInit()
    $pixels = New-Object byte[] ($Width * $Height * 4)
    $scaled.CopyPixels($pixels, $Width * 4, 0)
    return [Windows.Media.Imaging.BitmapSource]::Create($Width, $Height, 96, 96, [Windows.Media.PixelFormats]::Bgra32, $null, $pixels, $Width * 4)
}

function New-BgImage([string]$Path) {
    $width = 0
    $height = 0
    $stream = [IO.File]::OpenRead($Path)
    try {
        $probe = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::DelayCreation, [Windows.Media.Imaging.BitmapCacheOption]::OnDemand)
        $width = $probe.Frames[0].PixelWidth
        $height = $probe.Frames[0].PixelHeight
    } finally {
        $stream.Dispose()
    }
    if ($width -lt 1 -or $height -lt 1) { throw '图片尺寸无效' }
    if ([long]$width * $height -gt (50 * 1000 * 1000)) {
        throw ('图片尺寸过大（' + $width + 'x' + $height + '）')
    }

    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.CreateOptions = [Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
    if ($width -gt 2560) { $bitmap.DecodePixelWidth = 2560 }
    $bitmap.UriSource = New-Object Uri($Path)
    $bitmap.EndInit()
    $bitmap.Freeze()

    $image = New-Object Windows.Controls.Image
    $image.Source = $bitmap
    $image.Stretch = [Windows.Media.Stretch]::UniformToFill
    $image.SnapsToDevicePixels = $true
    $image.IsHitTestVisible = $false
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($image, [Windows.Media.BitmapScalingMode]::HighQuality)

    return [pscustomobject]@{ Element = $image; Width = $bitmap.PixelWidth; Height = $bitmap.PixelHeight }
}

function ConvertTo-BgGifFrames([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $stream = New-Object IO.MemoryStream (, $bytes)
    $gif = $null
    try {
        $gif = [System.Drawing.Image]::FromStream($stream)
        if ($gif.FrameDimensionsList.Count -lt 1) { throw 'GIF 缺少帧信息' }
        $dimension = New-Object System.Drawing.Imaging.FrameDimension ($gif.FrameDimensionsList[0])
        $count = $gif.GetFrameCount($dimension)
        if ($count -lt 1) { throw 'GIF 没有可解码帧' }
        if ($gif.Width -lt 1 -or $gif.Height -lt 1) { throw 'GIF 尺寸无效' }
        if ([long]$gif.Width * $gif.Height -gt $script:BgLimits.GifPixels) {
            throw ('GIF 尺寸过大（' + $gif.Width + 'x' + $gif.Height + '）')
        }

        $delays = New-Object System.Collections.ArrayList
        $rawDelays = $null
        try {
            $property = $gif.GetPropertyItem(0x5100)
            $rawDelays = $property.Value
        } catch { }
        for ($i = 0; $i -lt $count; $i++) {
            $hundredths = 10
            if ($rawDelays -and ($i * 4 + 3) -lt $rawDelays.Length) {
                $hundredths = [BitConverter]::ToInt32($rawDelays, $i * 4)
            }
            if ($hundredths -lt 2) { $hundredths = 10 }
            [void]$delays.Add($hundredths * 10)
        }

        $staticOnly = ($count -gt $script:BgLimits.GifFrames) -or
            (([long]$gif.Width * $gif.Height * $count) -gt $script:BgLimits.GifWorkPixels)

        $scale = 1.0
        if ($gif.Width -gt $script:BgLimits.GifWidth) {
            $scale = [double]$script:BgLimits.GifWidth / $gif.Width
        }
        $outWidth = [int][math]::Round($gif.Width * $scale)
        $outHeight = [int][math]::Round($gif.Height * $scale)
        if ($outWidth -lt 1 -or $outHeight -lt 1) { throw 'GIF 缩放失败' }

        $step = 1
        $perFrame = [long]$outWidth * $outHeight * 4
        if ($perFrame -gt 0) {
            $maxKeep = [math]::Max(1, [int][math]::Floor($script:BgLimits.GifBudgetBytes / $perFrame))
            if ($count -gt $maxKeep) {
                $step = [int][math]::Ceiling([double]$count / $maxKeep)
            }
        }

        $frames = New-Object System.Collections.ArrayList
        $outDelays = New-Object System.Collections.ArrayList
        $pending = 0
        $watch = [Diagnostics.Stopwatch]::StartNew()

        for ($i = 0; $i -lt $count; $i++) {
            $gif.SelectActiveFrame($dimension, $i) | Out-Null
            $bitmap = New-Object System.Drawing.Bitmap ($gif)
            try {
                $frameWidth = $bitmap.Width
                $frameHeight = $bitmap.Height
                $rectangle = New-Object System.Drawing.Rectangle 0, 0, $frameWidth, $frameHeight
                $data = $bitmap.LockBits($rectangle, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                try {
                    $stride = [math]::Abs($data.Stride)
                    $buffer = New-Object byte[] ($stride * $frameHeight)
                    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buffer, 0, $buffer.Length)
                } finally {
                    $bitmap.UnlockBits($data)
                }
                $source = [Windows.Media.Imaging.BitmapSource]::Create($frameWidth, $frameHeight, 96, 96, [Windows.Media.PixelFormats]::Bgra32, $null, $buffer, $stride)
                if ($scale -lt 1.0) { $source = Resize-BgBitmap $source $outWidth $outHeight }
                $source.Freeze()

                if ($staticOnly) {
                    if ($i -eq 0) {
                        [void]$frames.Add($source)
                        [void]$outDelays.Add(0)
                    }
                    break
                }
                if (($i % $step) -eq 0) {
                    [void]$frames.Add($source)
                    [void]$outDelays.Add($pending + [int]$delays[$i])
                    $pending = 0
                } else {
                    $pending += [int]$delays[$i]
                }
            } finally {
                $bitmap.Dispose()
            }
        }

        Write-BgLog ('gif decoded: source=' + $count + ' kept=' + $frames.Count + ' ' + $outWidth + 'x' + $outHeight + ' static=' + $staticOnly + ' ms=' + $watch.ElapsedMilliseconds)
        return [pscustomobject]@{
            Frames       = $frames.ToArray()
            Delays       = $outDelays.ToArray()
            Width        = $outWidth
            Height       = $outHeight
            StaticOnly   = $staticOnly
            SourceFrames = $count
            Image        = $gif
            Stream       = $stream
        }
    } catch {
        if ($gif) { try { $gif.Dispose() } catch { } }
        try { $stream.Dispose() } catch { }
        throw
    }
}

function Start-BgGifTimer {
    $state = $script:BgState
    if (-not $state.Frames -or $state.Frames.Count -le 1) { return }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $state.Index = 0
    $timer.Interval = [TimeSpan]::FromMilliseconds([math]::Max(20, [int]$state.Delays[0]))
    $timer.Add_Tick({ Step-BgGif })
    $state.Timer = $timer
    $timer.Start()
}

function Step-BgGif {
    $state = $script:BgState
    if ($state.Kind -ne 'gif' -or -not $state.Frames -or $state.Frames.Count -le 1) {
        if ($state.Timer) { try { $state.Timer.Stop() } catch { } }
        return
    }
    $state.Index = ($state.Index + 1) % $state.Frames.Count
    if ($state.Image) {
        try { $state.Image.Source = $state.Frames[$state.Index] } catch { }
    }
    if ($state.Timer) {
        $state.Timer.Interval = [TimeSpan]::FromMilliseconds([math]::Max(20, [int]$state.Delays[$state.Index]))
    }
}

function Find-BgFFmpeg {
    if ($script:BgFFmpegResolved) { return $script:BgFFmpeg }
    $script:BgFFmpegResolved = $true
    $script:BgFFmpeg = $null
    try {
        $candidates = New-Object System.Collections.ArrayList
        if ($script:ToolsRoot) { [void]$candidates.Add((Join-Path $script:ToolsRoot 'ffmpeg.exe')) }
        if ($script:ProjectRoot) {
            [void]$candidates.Add((Join-Path $script:ProjectRoot 'tools\ffmpeg.exe'))
            $bundles = @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'tools') -Directory -Filter 'ffmpeg*' -ErrorAction SilentlyContinue)
            foreach ($bundle in $bundles) {
                [void]$candidates.Add((Join-Path $bundle.FullName 'bin\ffmpeg.exe'))
                [void]$candidates.Add((Join-Path $bundle.FullName 'ffmpeg.exe'))
            }
        }
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $script:BgFFmpeg = $candidate
                return $script:BgFFmpeg
            }
        }
        $command = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
        if ($command) { $script:BgFFmpeg = $command.Source }
    } catch { }
    return $script:BgFFmpeg
}

function Get-BgCacheDir {
    $dir = Join-Path $env:LOCALAPPDATA 'CyberButler\bgcache'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-BgFileKey([string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $text = $Path + '|' + $item.Length + '|' + $item.LastWriteTimeUtc.Ticks
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
    } finally {
        $sha.Dispose()
    }
    return (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Invoke-BgProcess([string]$FilePath, [string[]]$Arguments, [int]$TimeoutMs) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = (($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch { }
        return -1
    }
    return $process.ExitCode
}

function Get-BgPoster([string]$Path) {
    $ffmpeg = Find-BgFFmpeg
    if (-not $ffmpeg) { return $null }
    try {
        $cache = Get-BgCacheDir
        $key = Get-BgFileKey $Path
        $poster = Join-Path $cache ($key + '.png')
        if (Test-Path -LiteralPath $poster) { return $poster }
        foreach ($seek in @('1', '0')) {
            Remove-Item -LiteralPath $poster -Force -ErrorAction SilentlyContinue
            $code = Invoke-BgProcess $ffmpeg @(
                '-y', '-hide_banner', '-loglevel', 'error',
                '-ss', $seek, '-i', $Path,
                '-frames:v', '1', '-vf', 'scale=1280:-2',
                $poster
            ) 20000
            if ($code -eq 0 -and (Test-Path -LiteralPath $poster) -and ((Get-Item -LiteralPath $poster).Length -gt 0)) {
                Write-BgLog ('poster written: ' + $poster)
                return $poster
            }
        }
        Remove-Item -LiteralPath $poster -Force -ErrorAction SilentlyContinue
    } catch { }
    return $null
}

function Get-BgTranscode([string]$Path) {
    if ((Get-BgKind $Path) -ne 'video') { return $null }
    $ffmpeg = Find-BgFFmpeg
    if (-not $ffmpeg) { return $null }
    try {
        $cache = Get-BgCacheDir
        $key = Get-BgFileKey $Path
        $output = Join-Path $cache ($key + '.mp4')
        if ((Test-Path -LiteralPath $output) -and ((Get-Item -LiteralPath $output).Length -gt 0)) { return $output }
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
        $code = Invoke-BgProcess $ffmpeg @(
            '-y', '-hide_banner', '-loglevel', 'error',
            '-i', $Path,
            '-t', '120', '-an',
            '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '27',
            '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
            $output
        ) 120000
        if ($code -eq 0 -and (Test-Path -LiteralPath $output) -and ((Get-Item -LiteralPath $output).Length -gt 0)) {
            Write-BgLog ('transcoded: ' + $Path + ' -> ' + $output)
            return $output
        }
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    } catch { }
    return $null
}

function New-BgMediaElement([string]$Path, [bool]$Animated) {
    $media = New-Object Windows.Controls.MediaElement
    $media.LoadedBehavior = if ($Animated) { 'Play' } else { 'Manual' }
    $media.UnloadedBehavior = 'Manual'
    $media.IsMuted = $true
    $media.Volume = 0
    $media.Stretch = [Windows.Media.Stretch]::UniformToFill
    $media.ScrubbingEnabled = $true
    $media.IsHitTestVisible = $false
    $media.SnapsToDevicePixels = $true

    $media.Add_MediaEnded({ Continue-BgMediaLoop })
    $media.Add_MediaOpened({ Handle-BgMediaOpened })
    $media.Add_MediaFailed({
        $message = ''
        try {
            if ($args.Count -gt 1 -and $args[1].ErrorException) { $message = $args[1].ErrorException.Message }
        } catch { }
        $script:BgState.LastMediaError = $message
        Handle-BgMediaFailed
    })
    return $media
}

function Start-BgPendingMedia {
    $state = $script:BgState
    if (-not $state.Media -or -not $state.PendingPath) { return }
    if ($state.PendingGen -ne $state.Generation) { return }
    if ($state.MediaStarted) { return }
    $state.MediaStarted = $true
    try {
        $state.Media.Source = New-Object Uri($state.PendingPath)
        $state.Media.Play()
    } catch {
        Write-BgLog ('media start failed: ' + $_.Exception.Message)
        Handle-BgMediaFailed
    }
}

function Queue-BgMediaStart {
    $state = $script:BgState
    if ($script:BgStartTimer) {
        try { $script:BgStartTimer.Stop() } catch { }
        $script:BgStartTimer = $null
    }
    if ($window.IsLoaded) {
        $timer = New-Object Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(220)
        $timer.Add_Tick({
            if ($script:BgStartTimer) { try { $script:BgStartTimer.Stop() } catch { } }
            Start-BgPendingMedia
        })
        $script:BgStartTimer = $timer
        $timer.Start()
    } else {
        $script:BgStartHandler = [Windows.RoutedEventHandler]{
            Start-BgPendingMedia
            try { $window.Remove_ContentRendered($script:BgStartHandler) } catch { }
        }
        $window.Add_ContentRendered($script:BgStartHandler)
    }
}

function Continue-BgMediaLoop {
    $state = $script:BgState
    if (-not $state.Media -or -not $state.Animated) { return }
    try {
        $state.Media.Position = [TimeSpan]::Zero
        $state.Media.Play()
    } catch { }
}

function Handle-BgMediaOpened {
    $state = $script:BgState
    if (-not $state.Media) { return }
    $state.Width = $state.Media.NaturalVideoWidth
    $state.Height = $state.Media.NaturalVideoHeight
    if (-not $state.Animated) {
        try {
            $state.Media.Pause()
            $state.Media.Position = [TimeSpan]::Zero
        } catch { }
    }
}

function Handle-BgMediaFailed {
    $state = $script:BgState
    if ($state.Kind -ne 'video' -or -not $state.Path) { return }
    $path = $state.Path
    Write-BgLog ('media failed: ' + $state.LastMediaError + ' | ' + $path)

    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -eq '.webm' -and -not $state.TranscodeTried) {
        $state.TranscodeTried = $true
        $transcoded = Get-BgTranscode $path
        if ($transcoded -and $state.Media) {
            $state.Transcoded = $transcoded
            $state.Warning = '当前系统缺少 WebM 解码器，已自动转为 MP4 缓存。'
            try {
                $state.Media.Source = New-Object Uri($transcoded)
                $state.Media.Play()
                Write-BgLog ('retrying with transcoded file: ' + $transcoded)
                return
            } catch { }
        }
    }

    $state.Warning = '视频无法播放（缺少解码器或文件损坏），已降级为静态背景。'
    if ($window) {
        $window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action]{ Apply-BgFallback }) | Out-Null
    }
}

function Apply-BgFallback {
    $state = $script:BgState
    $path = $state.Path
    $settings = $state.Settings
    if (-not $path) { return }

    [Windows.Input.Mouse]::OverrideCursor = [Windows.Input.Cursors]::Wait
    try {
        $poster = Get-BgPoster $path
        Stop-BgMedia
        $state.Settings = $settings
        if ($poster) {
            $image = New-BgImage $poster
            Set-BgVisual $image.Element
            $state.Kind = 'video'
            $state.Path = $path
            $state.Animated = $false
            $state.Image = $image.Element
            $state.Width = $image.Width
            $state.Height = $image.Height
            $state.Warning = '视频无法播放，已使用静态首帧。'
            Set-BgOverlay $true
            Write-BgLog ('fallback poster applied: ' + $poster)
        } else {
            Set-BgSolid
            $state.Warning = '视频无法播放，已恢复纯色背景。'
            Write-BgLog 'fallback solid colour applied'
        }
    } catch {
        Write-BgLog ('fallback failed: ' + $_.Exception.Message)
        Set-BgSolid
        $state.Warning = '视频无法播放，已恢复纯色背景。'
    } finally {
        [Windows.Input.Mouse]::OverrideCursor = $null
    }
    Show-BgPendingWarning
}

function Show-BgWarning([string]$Message) {
    if (-not $Message) { return }
    if (-not $script:BgInteractive) {
        Write-BgLog ('warning (silent): ' + $Message)
        return
    }
    $script:BgState.PendingWarning = $Message
    if ($window) {
        $window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action]{ Show-BgPendingWarning }) | Out-Null
    }
}

function Show-BgPendingWarning {
    $state = $script:BgState
    if (-not $state.PendingWarning) { return }
    $message = $state.PendingWarning
    $state.PendingWarning = ''
    if (-not $script:BgInteractive) { return }
    try {
        [Windows.MessageBox]::Show($message, (T '背景' 'Background'), 'OK', 'Warning') | Out-Null
    } catch { }
}

function Restart-UiBackground {
    if ($script:BgSuppressRestart) { return }
    $state = $script:BgState
    if (-not $state.Path) { return }
    if ($state.Kind -ne 'gif' -and $state.Kind -ne 'video') { return }
    $path = $state.Path
    $settings = $state.Settings
    Set-UiBackground $path $settings | Out-Null
}

function Close-BackgroundEngine {
    try { Stop-BgMedia } catch { }
    $script:BgClosed = $true
}

function Set-UiBackground {
    param([string]$Path, $Settings = $null)

    $result = [pscustomobject]@{
        Ok         = $false
        Kind       = 'none'
        Reason     = ''
        Warning    = ''
        Frames     = 0
        Width      = 0
        Height     = 0
        Animated   = $false
        Path       = $Path
        Transcoded = ''
    }

    $animated = $true
    if ($Settings -and ($Settings.PSObject.Properties.Name -contains 'enable_animated_bg')) {
        $animated = [bool]$Settings.enable_animated_bg
    }

    Stop-BgMedia
    $script:BgState.Settings = $Settings
    $script:BgState.Warning = ''
    $script:BgState.PendingWarning = ''

    if (-not $Path) {
        Set-BgSolid
        $result.Ok = $true
        Write-BgLog 'background cleared'
        return $result
    }

    $check = Test-BgFile $Path
    if (-not $check.Ok) {
        Set-BgSolid
        $script:BgState.Warning = $check.Reason
        $result.Reason = $check.Reason
        Write-BgLog ('rejected: ' + $check.Reason + ' | ' + $Path)
        return $result
    }

    try {
        switch ($check.Kind) {
            'image' {
                $image = New-BgImage $Path
                Set-BgVisual $image.Element
                $script:BgState.Kind = 'image'
                $script:BgState.Path = $Path
                $script:BgState.Animated = $false
                $script:BgState.Width = $image.Width
                $script:BgState.Height = $image.Height
                $script:BgState.Image = $image.Element
                Set-BgOverlay $true
                $result.Ok = $true
                $result.Kind = 'image'
                $result.Width = $image.Width
                $result.Height = $image.Height
            }
            'gif' {
                $gif = ConvertTo-BgGifFrames $Path
                $script:BgGifState.Image = $gif.Image
                $script:BgGifState.Stream = $gif.Stream

                $image = New-Object Windows.Controls.Image
                $image.Stretch = [Windows.Media.Stretch]::UniformToFill
                $image.SnapsToDevicePixels = $true
                $image.IsHitTestVisible = $false
                $image.Source = $gif.Frames[0]
                Set-BgVisual $image

                $script:BgState.Kind = 'gif'
                $script:BgState.Path = $Path
                $script:BgState.Frames = $gif.Frames
                $script:BgState.Delays = $gif.Delays
                $script:BgState.Index = 0
                $script:BgState.Image = $image
                $script:BgState.Width = $gif.Width
                $script:BgState.Height = $gif.Height
                $script:BgState.Animated = ($animated -and $gif.Frames.Count -gt 1)
                Set-BgOverlay $true
                if ($script:BgState.Animated) {
                    Start-BgGifTimer
                } elseif ($gif.StaticOnly) {
                    $script:BgState.Warning = 'GIF 过大，已降级为静态首帧。'
                }

                $result.Ok = $true
                $result.Kind = 'gif'
                $result.Frames = $gif.Frames.Count
                $result.Width = $gif.Width
                $result.Height = $gif.Height
                $result.Animated = $script:BgState.Animated
                $result.Warning = [string]$script:BgState.Warning
            }
            'video' {
                $posterPath = $null
                if (-not $animated) { $posterPath = Get-BgPoster $Path }

                if ($posterPath) {
                    $image = New-BgImage $posterPath
                    Set-BgVisual $image.Element
                    $script:BgState.Kind = 'video'
                    $script:BgState.Path = $Path
                    $script:BgState.Animated = $false
                    $script:BgState.Image = $image.Element
                    $script:BgState.Width = $image.Width
                    $script:BgState.Height = $image.Height
                    Set-BgOverlay $true
                    Write-BgLog ('static poster applied: ' + $Path)
                    $result.Ok = $true
                    $result.Kind = 'video'
                    $result.Width = $image.Width
                    $result.Height = $image.Height
                    $result.Animated = $false
                } else {
                    $media = New-BgMediaElement $Path $animated
                    Set-BgVisual $media
                    $script:BgState.Kind = 'video'
                    $script:BgState.Path = $Path
                    $script:BgState.Media = $media
                    $script:BgState.Animated = $animated
                    $script:BgState.Generation = [int]$script:BgState.Generation + 1
                    $script:BgState.PendingGen = $script:BgState.Generation
                    $script:BgState.PendingPath = $Path
                    $script:BgState.MediaStarted = $false
                    Set-BgOverlay $true
                    Queue-BgMediaStart
                    $result.Ok = $true
                    $result.Kind = 'video'
                    $result.Animated = $animated
                }
            }
        }
    } catch {
        $message = $_.Exception.Message
        Stop-BgMedia
        Set-BgSolid
        $script:BgState.Warning = $message
        $result.Reason = $message
        Write-BgLog ('apply failed: ' + $message + ' | ' + $Path)
        return $result
    }

    $result.Transcoded = [string]$script:BgState.Transcoded
    return $result
}

function Get-BgStateSnapshot {
    $state = $script:BgState
    $mediaState = ''
    if ($state.Media) {
        try { $mediaState = 'source=' + [IO.Path]::GetFileName([string]$state.Media.Source) } catch { }
        try { $mediaState += ' pos=' + [math]::Round($state.Media.Position.TotalSeconds, 2) } catch { }
        try { $mediaState += ' video=' + $state.Media.NaturalVideoWidth + 'x' + $state.Media.NaturalVideoHeight } catch { }
        try { $mediaState += ' muted=' + $state.Media.IsMuted } catch { }
    }
    $children = 0
    try { if ($backgroundLayer -is [Windows.Controls.Panel]) { $children = $backgroundLayer.Children.Count } } catch { }
    [pscustomobject]@{
        Kind       = $state.Kind
        Animated   = $state.Animated
        FrameCount = @($state.Frames).Count
        Width      = $state.Width
        Height     = $state.Height
        MediaState = $mediaState
        Children   = $children
        Warning    = $state.Warning
        Path       = $state.Path
        Transcoded = $state.Transcoded
    }
}

function Wait-BgDispatcher([int]$Milliseconds) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $Milliseconds) {
        try {
            [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Windows.Threading.DispatcherPriority]::Background, [Action]{}) | Out-Null
        } catch { }
        Start-Sleep -Milliseconds 40
    }
}

function Save-BgScreenshot([string]$Path) {
    try {
        $element = $window.Content
        if (-not $element) { return '' }
        $width = [int][math]::Max(640, $window.ActualWidth)
        $height = [int][math]::Max(480, $window.ActualHeight)
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($element)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create($Path)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
        return $Path
    } catch {
        Write-BgLog ('screenshot failed: ' + $_.Exception.Message)
        return ''
    }
}

function Invoke-BgSmokeTest([string]$AssetDir) {
    if (-not $AssetDir) { $AssetDir = $env:TEMP }
    $report = New-Object System.Collections.ArrayList

    $window.WindowStyle = 'None'
    $window.ShowInTaskbar = $false
    $window.Left = -6000
    $window.Top = -6000
    $window.Show()
    Wait-BgDispatcher 500

    $cases = @(
        @{ File = 'test.png'; Tag = 'png'; Animated = $true },
        @{ File = 'test.gif'; Tag = 'gif'; Animated = $true },
        @{ File = 'pillow-trans.gif'; Tag = 'gif-transparent'; Animated = $true },
        @{ File = 'test.gif'; Tag = 'gif-anim-off'; Animated = $false },
        @{ File = 'test.mp4'; Tag = 'mp4'; Animated = $true },
        @{ File = 'test.mp4'; Tag = 'mp4-loop'; Animated = $true; Wait = 4200 },
        @{ File = 'test.mp4'; Tag = 'mp4-anim-off'; Animated = $false },
        @{ File = 'test.webm'; Tag = 'webm'; Animated = $true },
        @{ File = 'test.webm'; Tag = 'webm-anim-off'; Animated = $false },
        @{ File = 'broken.mp4'; Tag = 'broken'; Animated = $true }
    )

    foreach ($case in $cases) {
        $path = Join-Path $AssetDir $case.File
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $settings = [pscustomobject]@{ enable_animated_bg = [bool]$case.Animated }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Set-UiBackground $path $settings
        $loadMs = $watch.ElapsedMilliseconds
        $wait = 1800
        if ($case.ContainsKey('Wait')) { $wait = [int]$case.Wait }
        Wait-BgDispatcher $wait
        $snapshot = Get-BgStateSnapshot

        $shots = @()
        if ($case.Tag -eq 'gif' -or $case.Tag -eq 'gif-transparent') {
            $first = Save-BgScreenshot (Join-Path $AssetDir ('bgshot-' + $case.Tag + '-1.png'))
            Wait-BgDispatcher 260
            $second = Save-BgScreenshot (Join-Path $AssetDir ('bgshot-' + $case.Tag + '-2.png'))
            if ($first) { $shots += $first }
            if ($second) { $shots += $second }
        }

        [void]$report.Add([pscustomobject]@{
            tag         = $case.Tag
            file        = $case.File
            ok          = $result.Ok
            kind        = $snapshot.Kind
            animated    = $snapshot.Animated
            frames      = $snapshot.FrameCount
            width       = $snapshot.Width
            height      = $snapshot.Height
            load_ms     = $loadMs
            media       = $snapshot.MediaState
            warning     = $snapshot.Warning
            reason      = $result.Reason
            screenshots = $shots
        })
    }

    Set-UiBackground '' $null | Out-Null
    Wait-BgDispatcher 200
    $cleared = Get-BgStateSnapshot
    [void]$report.Add([pscustomobject]@{
        tag    = 'cleared'
        file   = ''
        ok     = $true
        kind   = $cleared.Kind
        frames = $cleared.FrameCount
        media  = $cleared.MediaState
        reason = ''
    })

    # Closing the settings dialog without saving must restore the persisted
    # background; saving first must keep the preview.
    $pngPath = Join-Path $AssetDir 'test.png'
    $gifPath = Join-Path $AssetDir 'test.gif'
    if ((Test-Path -LiteralPath $pngPath) -and (Test-Path -LiteralPath $gifPath)) {
        $script:BgOriginal = @{ background = $pngPath; anim = $true }
        $script:BgPreview = [pscustomobject]@{
            theme = 'light'; language = 'zh'
            background = $gifPath; enable_animated_bg = $true
        }
        $script:BgCommitted = $false
        Set-UiBackground $script:BgPreview.background $script:BgPreview | Out-Null
        Revert-BgPreview
        $reverted = Get-BgStateSnapshot
        [void]$report.Add([pscustomobject]@{
            tag    = 'revert-on-close'
            file   = ''
            ok     = ($reverted.Path -eq $pngPath)
            kind   = $reverted.Kind
            frames = $reverted.FrameCount
            media  = [IO.Path]::GetFileName($reverted.Path)
            reason = ''
        })

        $script:BgCommitted = $true
        $script:BgPreview.background = $gifPath
        Set-UiBackground $gifPath $script:BgPreview | Out-Null
        Revert-BgPreview
        $kept = Get-BgStateSnapshot
        [void]$report.Add([pscustomobject]@{
            tag    = 'revert-after-save'
            file   = ''
            ok     = ($kept.Path -eq $gifPath)
            kind   = $kept.Kind
            frames = $kept.FrameCount
            media  = [IO.Path]::GetFileName($kept.Path)
            reason = ''
        })

        Set-UiBackground '' $null | Out-Null
        $script:BgCommitted = $false
        $script:BgOriginal = $null
        $script:BgPreview = $null
    }

    $window.Close()
    return $report
}

if ($window -and -not $script:BgCleanupBound) {
    $window.Add_Closed({ Close-BackgroundEngine })
    $script:BgCleanupBound = $true
}
