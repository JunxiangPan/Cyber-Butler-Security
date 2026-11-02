from __future__ import annotations

import sbom


def test_sbom_round_trip_and_tamper(tmp_path):
    req = tmp_path / "requirements.txt"
    req.write_text("requests==2.32.0\nurllib3==2.2.0\n", encoding="utf-8")
    manifest = tmp_path / "requirements.sbom.json"
    sbom.build(req, manifest)
    assert sbom.verify(req, manifest)[0] is True

    req.write_text("requests==2.32.1\nurllib3==2.2.0\n", encoding="utf-8")
    ok, reason = sbom.verify(req, manifest)
    assert ok is False
    assert "hash" in reason
