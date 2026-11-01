# PyInstaller policy

This repository does not currently ship a PyInstaller `.spec`. The native
launcher in `build/CyberButlerLauncher.cs` is built by `build/build-launcher.ps1`
with the in-box C# compiler; Python services run from their venv.

If a future component is packaged with PyInstaller, use only:

```text
--onedir
--noupx
--clean
--noconfirm
--windowed
--version-file build/version_info.txt
--manifest build/app.manifest
```

Do not use:

```text
--onefile
UPX
--key / obfuscation
runtime DLL unpacking
```

Sign every resulting `.exe` and `.dll` with Authenticode after the build, then
timestamp the signature. `app.manifest` is `asInvoker`; elevation belongs to the
installer launcher, not every agent process.
