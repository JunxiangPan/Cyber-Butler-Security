# v1.1.1 — Layered Dashboard Backgrounds

## Added

- `tools/dashboard_background.ps1`: layered background engine.
  - `BackgroundLayer` is now a dedicated `Grid` with `IsHitTestVisible="False"`
    under the overlay and the dashboard content, so buttons stay clickable and
    no background element can swallow input.
  - static images: png / jpg / jpeg / bmp;
  - animated GIF: decoded natively with `System.Drawing` (no NuGet package),
    frames are frozen `BitmapSource`s swapped by a `DispatcherTimer`;
  - video: `MediaElement` with `LoadedBehavior="Play"`,
    `UnloadedBehavior="Manual"`, `MediaEnded` looping and `IsMuted="True"`.
- `enable_animated_bg` setting: when disabled, GIFs fall back to their first
  frame and videos to a poster frame (or a paused first frame), so a slow
  machine can keep a static background.
- Settings dialog:
  - file filter now includes gif / mp4 / webm;
  - `清除动态背景（恢复纯色）` button;
  - `启用动态背景（GIF/视频）` checkbox;
  - performance hint for animated/video backgrounds;
  - live preview with revert-on-close: closing without saving restores the
    persisted background and releases the preview media element.
- Background cache in `%LOCALAPPDATA%\CyberButler\bgcache` for poster frames and
  WebM → MP4 transcodes; diagnostic log in
  `%LOCALAPPDATA%\CyberButler\background.log`.

## Why no NuGet

WPF's `GifBitmapDecoder` returns raw sub-rectangle frames and ignores the GIF
transparent colour index and disposal method. A naive frame-by-frame player
therefore renders broken frames. `System.Drawing` (GDI+, part of .NET
Framework) composites GIF frames correctly — verified pixel-for-pixel against
Pillow reference frames — at about 4–5 ms per 640×360 frame, so no external
package is shipped.

## Video reality check

`MediaElement` uses Windows Media Foundation. H.264 MP4 plays on a stock
Windows 10/11 install. WebM (VP8/VP9) needs a system decoder that is often
missing; when that happens the engine transcodes the file once to a cached MP4
with a local `ffmpeg.exe` if one is available, otherwise it falls back to a
poster frame or the solid theme colour with a clear warning.

## Safety and limits

- Rejects files whose extension and magic bytes disagree, empty files and
  files above: images 64 MB, GIF 96 MB, video 256 MB.
- Caps GIF work: 400 source frames, 16 MP, 120 M composited pixels, 128 MB of
  frame cache, 1280 px maximum width.
- `MediaElement.Stop()` + `Close()` + `Source = $null` on every background
  switch, theme switch, settings-dialog revert and window close.
- Video is always muted (`IsMuted = True`, `Volume = 0`).

## Verification

```text
DASHBOARD_XAML_OK
DASHBOARD_SETTINGS_OK
MERGED=2 DARK_PAGE=#FF1E1E24 LIGHT_PAGE=#FFF5F6F8 CONTAINS=True
SETTINGS_DIALOG_OK
background smoke: png / gif / transparent gif / mp4 / mp4 loop / webm /
                  webm static / corrupt mp4 / revert-on-close / clear
```

Measured on the build machine:

```text
png   1280x720   load  38 ms
gif   24 frames  load 163 ms  (4.6 ms/frame decode+composite)
mp4   640x360    load  26 ms  playing, muted, loops at 3 s
webm  VP9        auto-transcoded to MP4, then played
corrupt mp4      rejected by the media pipeline, solid fallback
```
