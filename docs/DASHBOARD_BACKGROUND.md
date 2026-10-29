# Dashboard background engine

The dashboard window is built from three layers:

```text
WindowRoot
├── BackgroundLayer   Grid, IsHitTestVisible = False
│   ├── Image                     png / jpg / bmp
│   ├── Image + DispatcherTimer   animated gif
│   └── MediaElement              mp4 / webm
├── BackgroundOverlay Border      theme wash, IsHitTestVisible = False
└── RootGrid                      tabs, cards, buttons
```

`BackgroundLayer.Background` stays bound to the theme `PageBrush`, so clearing
a background immediately returns to the theme colour. Every visual child is
non-interactive: the layer and `MediaElement` both set
`IsHitTestVisible="False"`, which is inherited by the children.

## Supported files

| Kind | Extensions | Renderer | Loop |
| --- | --- | --- | --- |
| Static image | `.png` `.jpg` `.jpeg` `.bmp` | `Image`, `Stretch=UniformToFill` | — |
| Animated GIF | `.gif` | GDI+ frame decoder + `DispatcherTimer` | frame delays from `PropertyTagFrameDelay` |
| Video | `.mp4` | `MediaElement` (Windows Media Foundation) | `MediaEnded` → `Position=0` + `Play()` |
| Video | `.webm` | same, only when the system has a WebM decoder | auto-transcoded to cached MP4 when `ffmpeg.exe` is present |

Video is always muted: `IsMuted="True"` and `Volume=0`. `LoadedBehavior` is
`Play` for animated mode and `Manual` for the static (poster) mode;
`UnloadedBehavior` is always `Manual`.

## Why the GIF path is custom

WPF's `GifBitmapDecoder` exposes sub-rectangle frames (`/imgdesc/Left`,
`/imgdesc/Top`) and ignores `/grctlext/TransparencyFlag`. Playing those frames
directly shows moving strips on a black background.

`dashboard_background.ps1` instead reads the GIF with `System.Drawing`, which
composites offsets, transparency and disposal correctly, then converts each
composited frame to a frozen `BitmapSource`. Measured cost: 24 frames of
640×360 in ~111 ms (≈4.6 ms per frame). No NuGet package is required.

## Limits and fallbacks

| Limit | Value |
| --- | --- |
| Image size | 64 MB, ≤ 50 MP |
| GIF size | 96 MB, ≤ 16 MP, ≤ 400 source frames |
| GIF composition work | 120 M pixels |
| GIF frame cache | 128 MB, max width 1280 px |
| Video size | 256 MB |

- Extension and magic bytes must agree (`ftyp` for MP4, EBML header for WebM,
  `GIF8`, `BM`, PNG/JPEG signatures). A mismatch is rejected before decoding.
- Oversized or corrupt files return a reason; the settings dialog shows
  `文件过大或格式不支持` with the detail and keeps the previous background.
- A video that fails to open triggers, in order: WebM transcode (if applicable
  and ffmpeg exists) → ffmpeg poster frame → solid theme colour. The reason is
  written to `%LOCALAPPDATA%\CyberButler\background.log`.
- `enable_animated_bg = false` forces GIFs to their first frame and videos to a
  poster frame (or a paused first frame when ffmpeg is unavailable).

## Settings

`%LOCALAPPDATA%\CyberButler\dashboard-settings.json`

```json
{
  "theme": "light",
  "language": "zh",
  "background": "D:\\Pictures\\loop.gif",
  "enable_animated_bg": true
}
```

The settings dialog previews immediately. `保存设置` persists and keeps the
preview; closing the dialog without saving restores the persisted background
and calls `Stop()` / `Close()` on the preview `MediaElement`.

## Cache

`%LOCALAPPDATA%\CyberButler\bgcache` holds poster frames (`<sha1>.png`) and
WebM transcodes (`<sha1>.mp4`). They are keyed by path + size + mtime and are
safe to delete.

## Maintenance checks

```powershell
powershell -NoProfile -Sta -ExecutionPolicy Bypass -File tools\cyber_butler_dashboard.ps1 `
  -ProjectRoot D:\qq苏瑾言大肥鱼 -SmokeTest
powershell -NoProfile -Sta -ExecutionPolicy Bypass -File tools\cyber_butler_dashboard.ps1 `
  -ProjectRoot D:\qq苏瑾言大肥鱼 -SmokeSettings
powershell -NoProfile -Sta -ExecutionPolicy Bypass -File tools\cyber_butler_dashboard.ps1 `
  -ProjectRoot D:\qq苏瑾言大肥鱼 -SmokeSettingsDialog -SmokeSettingsShot shot.png
powershell -NoProfile -Sta -ExecutionPolicy Bypass -File tools\cyber_butler_dashboard.ps1 `
  -ProjectRoot D:\qq苏瑾言大肥鱼 -SmokeBackground -SmokeAssetDir C:\path\to\media
```

`-SmokeBackground` prints a JSON report: format, element kind, frame count,
load time, `MediaElement` state (source, position, natural size, mute flag),
warnings, and the revert-on-close / revert-after-save checks. It also writes
two screenshots 260 ms apart for GIF cases so animation can be verified by
comparing the files.
