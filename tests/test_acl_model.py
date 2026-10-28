"""ACL deny-path *logic model* — not a real Windows kernel ACL test.

This is a CI-safe model of the Windows deny-ACE semantics used by
``tools/secure_totp_vault.ps1``: an explicit deny for the service account must
win over any inherited allow. It does not create a Windows SID, does not run as
the service account, and does not query the kernel ACL.

The real Windows ACL is checked during the manual Windows acceptance test
described in SECURITY.md.
"""

from __future__ import annotations

from dataclasses import dataclass

import pytest


@dataclass(frozen=True)
class Ace:
    principal: str
    allow: bool
    rights: frozenset[str]


def effective_access(aces: list[Ace], principal: str, right: str) -> bool:
    """Return False if an explicit deny matches; allow only an explicit allow."""
    denied = aces_principal_rights(aces, principal, allow=False)
    if "full" in denied or right in denied:
        return False
    allowed = aces_principal_rights(aces, principal, allow=True)
    return "full" in allowed or right in allowed


def aces_principal_rights(
    aces: list[Ace], principal: str, *, allow: bool
) -> frozenset[str]:
    result: set[str] = set()
    for ace in aces:
        if ace.principal.lower() != principal.lower() or ace.allow != allow:
            continue
        result.update(ace.rights)
    return frozenset(result)


def read_vault(path: str, principal: str, aces: list[Ace]) -> str:
    """Simulate opening the vault; deny must be a PermissionError."""
    if not effective_access(aces, principal, "read"):
        raise PermissionError(f"access to {path} denied for {principal}")
    return "vault-contents-never-read-in-this-test"


def test_service_account_is_denied_even_if_an_allow_ace_exists() -> None:
    aces = [
        Ace("YOUR_SERVICE_USER", False, frozenset({"full"})),
        Ace("YOUR_SERVICE_USER", True, frozenset({"read"})),
    ]

    with pytest.raises(PermissionError):
        read_vault(
            r"YOUR_USER_PATH\Documents\苏瑾言TOTP保险箱",
            "YOUR_SERVICE_USER",
            aces,
        )


def test_owner_can_read_vault() -> None:
    aces = [Ace("YOUR_USER_NAME", True, frozenset({"full"}))]
    assert read_vault("vault", "YOUR_USER_NAME", aces).startswith("vault-")


def test_unrelated_account_is_denied_by_default() -> None:
    aces = [Ace("YOUR_USER_NAME", True, frozenset({"full"}))]
    with pytest.raises(PermissionError):
        read_vault("vault", "YOUR_SERVICE_USER", aces)
