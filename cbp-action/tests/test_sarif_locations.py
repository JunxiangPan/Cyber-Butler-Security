"""Every SARIF finding must carry an artifactLocation."""
from pathlib import Path
from cbp.sarif import build


def test_every_result_has_artifact_location(tmp_path: Path) -> None:
    doc = build([
        ("encoding", False, "src/a.py: UTF-8 BOM"),
        ("custom", False, "src/a.py:2: [CBP-CST-001] bad"),
        ("coverage", False, "core=10.00%/80.00%"),
    ], tmp_path)
    assert doc["runs"][0]["results"]
    for result in doc["runs"][0]["results"]:
        assert result["locations"][0]["physicalLocation"]["artifactLocation"]["uri"]
