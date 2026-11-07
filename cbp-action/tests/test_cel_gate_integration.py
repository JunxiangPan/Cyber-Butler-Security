"""The five policy gates apply their CEL decision after detection."""
import pytest
from cbp.config import GateConfig
from cbp import claims_gate, comment_gate, custom_rules, dependency_gate, docs_gate

MODULES = [
    ("comments", comment_gate),
    ("claims", claims_gate),
    ("dependency", dependency_gate),
    ("docs", docs_gate),
    ("custom", custom_rules),
]


@pytest.mark.parametrize("gate,module", MODULES)
def test_gate_uses_cel_policy(gate, module, tmp_path, monkeypatch):
    monkeypatch.setattr(module, "_detect", lambda cfg: (False, "detected"))
    cfg = GateConfig(root=tmp_path, cel_policies={gate: "true"})
    passed, detail = module.run(cfg)
    assert passed is True and detail == "detected"


@pytest.mark.parametrize("gate,module", MODULES)
def test_gate_can_fail_via_cel(gate, module, tmp_path, monkeypatch):
    monkeypatch.setattr(module, "_detect", lambda cfg: (True, "clean"))
    cfg = GateConfig(root=tmp_path, cel_policies={gate: "false"})
    passed, _detail = module.run(cfg)
    assert passed is False
