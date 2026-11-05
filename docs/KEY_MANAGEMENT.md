# Key Management (Draft)

Status: draft for human review. No signing key is moved or exported by this
document.

## Recommended storage

- Release private key on an offline machine or a hardware-backed keystore.
- If Windows DPAPI is used, bind it to a dedicated signing account, not the
  desktop user and not SYSTEM.
- Keep an encrypted backup in a separate physical location.
- Never place the private key in the repository, the release bundle or a CI
  artifact.

## Signing ceremony

1. Human reviews the challenge, BUILD_REPORT and acceptance proof.
2. A second person confirms the package hash out of band.
3. Sign only the manifest with the RSA key; never sign a mutable directory.
4. Record the signer, time, package SHA-256, report SHA-256 and host IP in an
   append-only signing log.
5. Compare the resulting signature with the public key before upload.

## Leak response

1. Stop signing and remove the public key from update metadata.
2. Publish a revocation notice for every release signed with the key.
3. Generate a new key on the offline machine.
4. Rebuild and re-sign only after the incident review.
5. Preserve logs; do not delete the compromised key material until the review
   is complete.

## Not implemented yet

- Hardware token enforcement.
- Two-person approval in software.
- Append-only remote signing log.
