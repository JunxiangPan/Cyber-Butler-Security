# A1 install-media requirements

Status: **A1_BLOCKED_INSTALL_MEDIA — paused.**

We are not retrying the current ISO, Gen1, IDE, or Secure Boot combinations.

## Accepted media

One of:

1. A Windows 11 ISO verified to boot under UEFI/Hyper-V Gen2.
2. A clean Windows 11 VHDX with no `C:\CyberButler`, CBS service, or Python
   runtime.

## ISO preflight

Before creating a VM, verify:

```text
efi\boot\bootx64.efi
sources\boot.wim
bootmgr.efi
```

Record the ISO SHA-256 in `quality/a1/artifacts/a1-media.json`.

## VHDX preflight

Before cloning, verify inside the VHDX:

```text
no C:\CyberButler
no CyberButlerAgentRuntime service
no Python runtime
```

Record the VHDX SHA-256 in `quality/a1/artifacts/a1-media.json`.

## Current environment

No suitable clean Windows VHDX is available. `cbs-acceptance-vm` and `CBS-Test`
are not clean baselines and must not be used.
