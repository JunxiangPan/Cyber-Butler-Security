from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
STATUS = json.loads((ROOT / "docs/_data/status-v1.6.2.json").read_text(encoding="utf-8"))
README_LANGS = [
    "README_en.md",
    "README_zh.md",
    "README_de.md",
    "README_es.md",
    "README_fr.md",
    "README_ja.md",
    "README_ko.md",
    "README_ru.md",
]


def test_status_is_canonical_and_complete():
    assert STATUS["version"] == "1.6.2"
    assert "6185" in STATUS["ports"]
    assert "CyberButlerAstrBot" in " ".join(STATUS["completed"])
    assert any("WFP enforce" in item for item in STATUS["not_completed"])


def test_eight_language_readmes_mirror_status():
    for name in README_LANGS:
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "CyberButlerAstrBot" in text, name
        assert "6199" in text, name
        assert "S4U" in text, name
        assert "status-v1.6.2.json" in text, name
        assert "known-limitations.md" in text, name
        assert "why-not-faq.md" in text, name
        assert any(marker in text for marker in (
            "Status at a glance", "状态红绿灯", "Status auf einen Blick",
            "Estado de un vistazo", "État en un coup", "一目でわかる状態",
            "한눈에 보는 상태", "Статус с первого взгляда",
        )), name


def test_wfp_code_and_status_do_not_claim_enforcement():
    code = (ROOT / "tools/wfp_guard.py").read_text(encoding="utf-8")
    docs = (ROOT / "docs/10-security/wfp-network-policy.md").read_text(encoding="utf-8")
    assert "ENFORCE_IMPLEMENTED = False" in code
    assert "audit" in docs.lower()
    assert "not implemented" in docs.lower()


def test_6199_owned_by_adapter_not_service():
    ports = STATUS["ports"]
    assert "6199" in ports
    assert "OneBot" in ports["6199"]
    assert "not a system service" in ports["6199"]
    for name in README_LANGS:
        assert "OneBot" in (ROOT / name).read_text(encoding="utf-8"), name


def test_active_markdown_links_and_fences():
    active = [ROOT / name for name in ["README.md", *README_LANGS, "SECURITY.md", "README-INSTALL.md"]]
    for path in (ROOT / "docs").rglob("*.md"):
        rel = str(path).replace("\\", "/")
        if "/legacy-readmes/" in rel or "/archive/" in rel or "/releases/" in rel:
            continue
        active.append(path)
    link_re = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for path in active:
        text = path.read_text(encoding="utf-8")
        assert text.count("```") % 2 == 0, f"unbalanced fence: {path}"
        for target in link_re.findall(text):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#", 1)[0].strip()
            if not target or "YOUR_" in target or "<" in target:
                continue
            assert (path.parent / target).resolve().exists(), f"broken link {target} in {path}"


def test_archived_documents_are_marked():
    archive = ROOT / "docs/40-history/archive"
    if archive.exists():
        for path in archive.rglob("*.md"):
            text = path.read_text(encoding="utf-8")
            assert "[ARCHIVED" in text or "ARCHIVED - 已废弃" in text, str(path)


def test_documentation_issue_form_exists():
    form = (ROOT / ".github/ISSUE_TEMPLATE/documentation.yml").read_text(encoding="utf-8")
    assert "Documentation" in form
    assert "labels:" in form


def test_contributors_acknowledged_everywhere():
    contributors = (ROOT / "CONTRIBUTORS.md").read_text(encoding="utf-8")
    for name in [
        "Practical-Craft4967", "QuanTradin", "Reid Marlow", "Auten",
        "mp3sss", "More-Ad7285", "HeartMaleficent35", "rikulauttia",
        "Sandy", "程序员阿江", "牧羊人AILab", "若宸", "墨莘子凌",
    ]:
        assert name in contributors, name
    assert "CBS 的架构不是由作者一个人闭门造车想出来的，而是全球开源社区共同打磨的结晶。" in contributors
    assert "CONTRIBUTORS.md" in (ROOT / "README.md").read_text(encoding="utf-8")
    for path in (ROOT / "docs/releases").glob("*.md"):
        assert "CONTRIBUTORS.md" in path.read_text(encoding="utf-8"), str(path)
