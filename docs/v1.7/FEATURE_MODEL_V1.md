# v1.7.0 Feature Model — Phase 1/2 status

## Implemented

- `installer/features.v1.json`
- `installer/lib/Installer.Features.ps1` with `Resolve-CyberButlerFeatures`
- Required features: `core`, `broker`, `audit`, `approval.totp`, one approval channel
- Presets:
  - Light: `core, broker, audit, approval.totp, approval.qq`
  - Medium: Light + `webui`
  - High: Medium + `wfp_guard`
- `approval.qq` requires `OwnerQQ`; does not require email/SMTP
- `approval.email` requires email + SMTP fields and `otp_mailer`; does not require `OwnerQQ`
- mutual exclusion of `approval.qq` / `approval.email`
- dependency/exclusion resolution
- `Custom (based on Tier)` label
- below-minimum requires `-AcceptBelowMinimum` and records `SecurityFloorWaived`
- backend params: `-FeatureIds`, `-ApprovalChannel`, `-AcceptBelowMinimum`
- report fields: `selected_features`, `required_features`, `approval_channel`, `security_floor`, `security_floor_waived`
- resolver tests: 12 passed

## Not yet complete

- Feature dialog now renders dynamic checkboxes, tier presets, disabled required items, QQ/Email conditional fields, Custom label and below-minimum waiver confirmation.
- The main WPF form still shows email/SMTP fields; the feature dialog is the authoritative selection. Installer component branching is still tier-based.
- Service task registration is now gated by selected features (broker/webui/otp_mailer/wfp_guard).
- Core payload deployment still copies the common payload; WebUI/AuxRuntime files are not yet removed for unselected features.
- WebUI login identity is not yet decoupled in the GUI; email/SMTP fields remain visible.

These are release blockers for v1.7.0, not accepted as complete.
