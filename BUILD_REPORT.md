# BUILD_REPORT

## self-seal record
```text
SELF_SEAL_RECORDED files=13
EXIT_CODE=0
```
ChallengeCode: A-READY-20261105-2320
- Generated: 2026-11-05T12:50:25.9425381Z
- Host: PCVP
- Pipeline SHA256: 8A56196167897FAD2F4140588829681E01C00F84B4E76B1E9249EB2E6169C2BD
- MAC: , 00-FF-E3-4C-48-3F, 00-15-5D-52-C3-ED, 34-5A-60-51-09-DD, 00-15-5D-01-6F-0C, DA-7A-22-89-5F-24, , , FA-B3-2F-2D-F4-15, 00-E0-4C-68-02-27
- VERSION: 1.6.3

## forbidden terms / private paths in all text
```text
TEXT_HYGIENE_OK
EXIT_CODE=0
```
## packaging preflight
```text
PACKAGING_GATES_OK
EXIT_CODE=0
```
## test PowerShell syntax
```text
PS_TESTS_PARSED=48
PS_TESTS_ERRORS=0
EXIT_CODE=0
```
## code comments (AST)
```text
CODE_COMMENT_GATE_OK
python_functions=520 missing_docstrings=0 powershell_functions=454 missing_block_comments=0
EXIT_CODE=0
```
## docs consistency
```text
DOC_CONSISTENCY_GATE_OK
EXIT_CODE=0
```
- Launcher version: 1.6.3.0
## static types/dead code/PSScriptAnalyzer
```text
===== mypy (exit 0) =====
Success: no issues found in 53 source files
===== pyright (exit 0) =====
d:\qq苏瑾言大肥鱼\public-release\installer\lib\totp_material.py
  d:\qq苏瑾言大肥鱼\public-release\installer\lib\totp_material.py:86:20 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
  d:\qq苏瑾言大肥鱼\public-release\installer\lib\totp_material.py:104:16 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
d:\qq苏瑾言大肥鱼\public-release\tools\audit_chain.py
  d:\qq苏瑾言大肥鱼\public-release\tools\audit_chain.py:83:20 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
d:\qq苏瑾言大肥鱼\public-release\tools\broker.py
  d:\qq苏瑾言大肥鱼\public-release\tools\broker.py:44:12 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
d:\qq苏瑾言大肥鱼\public-release\tools\setup_totp.py
  d:\qq苏瑾言大肥鱼\public-release\tools\setup_totp.py:14:8 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
0 errors, 5 warnings, 0 informations
===== vulture (exit 0) =====

===== PSScriptAnalyzer (exit 0) =====
PSSA_FILES=81
PSSA_FINDINGS=0
STATIC_GATE_OK
EXIT_CODE=0
```
## test integrity (MANIFEST + snapshot + empty-assert AST)
```text
TEST_INTEGRITY_OK files=82
EXIT_CODE=0
```
## mutation check (real assertion inversion)
```text
TARGET D:\qq苏瑾言大肥鱼\public-release\tests\test_acl_effective.py:16 test_kernel_acl_denies_write
ORIGINAL assert user
MUTATED  assert not user
EXIT=1 KILLED=True
RESTORED=True SHA256=2b528e8f0166bc890004c85aae390f83e80d89f4758bf155626c5250e76e114b
TARGET D:\qq苏瑾言大肥鱼\public-release\tests\test_approval_i18n.py:11 test_all_supported_languages_have_technical_header
ORIGINAL assert header
MUTATED  assert not header
EXIT=1 KILLED=True
RESTORED=True SHA256=d2aac531f2d7d181d7595db7c89418da98ec79ef8254d54825585d8b8a0d03be
TARGET D:\qq苏瑾言大肥鱼\public-release\tests\test_approval_i18n.py:18 test_manifest_prompt_formats_count
ORIGINAL assert "3" in approval_i18n.t("manifest", count=3)
MUTATED  assert not "3" in approval_i18n.t("manifest", count=3)
EXIT=1 KILLED=True
RESTORED=True SHA256=d2aac531f2d7d181d7595db7c89418da98ec79ef8254d54825585d8b8a0d03be
TARGET_1=tests\test_acl_effective.py:16 assert user -> assert not user
TARGET_2=tests\test_approval_i18n.py:11 assert header -> assert not header
TARGET_3=tests\test_approval_i18n.py:18 assert "3" in approval_i18n.t("manifest", count=3) -> assert not "3" in approval_i18n.t("manifest", count=3)
ALL_TURNED_RED=True
RESTORE_OK=True
MUTATION_OK
EXIT_CODE=0
```
## source mutation (production logic)
```text
MUTATION tools/broker.py: if action == "delete" and target.is_dir(): -> if action == "delete" and False: exit=1 restored=True
MUTATION tools/broker.py: if not _url_host_allowed(raw_path): -> if False: exit=1 restored=True
MUTATION tools/broker.py: scoped_minutes = 0 -> scoped_minutes = 30 exit=1 restored=True
MUTATION_OK
EXIT_CODE=0
```
## silent failure scan
```text
SILENT_FAILURE_GATE_OK
EXIT_CODE=0
```
## real Broker fixture (subprocess, HTTP, TOTP, trash, replay)
```text
CASE=no_token METHOD=GET PATH=/pending HTTP=403 BODY={"ok": false, "error": "unauthorized"}
CASE=no_token_request METHOD=POST PATH=/request HTTP=403 BODY={"ok": false, "error": "unauthorized"}
CASE=no_token_verify METHOD=POST PATH=/verify HTTP=403 BODY={"ok": false, "error": "unauthorized"}
CASE=no_token_trash METHOD=GET PATH=/trash HTTP=403 BODY={"ok": false, "error": "unauthorized"}
CASE=no_token_trash_undo METHOD=POST PATH=/trash/undo HTTP=403 BODY={"ok": false, "error": "unauthorized"}
CASE=forged_token METHOD=POST PATH=/request HTTP=403 BODY={"ok": false, "error": "unauthorized"}
CASE=request_delete METHOD=POST PATH=/request HTTP=200 BODY={"ok": true, "status": "requires_totp", "id": "c8988fbd30c3", "channel": "webui", "challenge": "", "action": "delete", "target": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixtur
CASE=bad_totp METHOD=POST PATH=/verify HTTP=403 BODY={"ok": false, "error": "invalid verification code", "attempts": 1}
CASE=bad_totp_second METHOD=POST PATH=/verify HTTP=403 BODY={"ok": false, "error": "invalid verification code", "attempts": 2}
CASE=good_totp METHOD=POST PATH=/verify HTTP=200 BODY={"ok": true, "id": "c8988fbd30c3", "result": "文件已移入两阶段暂存回收站，10 分钟内可撤回：c8988fbd30c3", "undo_available": true, "trash_id": "c8988fbd30c3", "undo_expires_at": "2026-11-05T13:01:15+00:
CASE=trash_list METHOD=GET PATH=/trash HTTP=200 BODY={"ok": true, "items": [{"id": "c8988fbd30c3", "original_path": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixture-1rbzm5au\\shared\\fixture-delete.txt", "expires_at": "2026-11-05
CASE=replay_request METHOD=POST PATH=/request HTTP=200 BODY={"ok": true, "status": "requires_totp", "id": "96f3555ee3f2", "channel": "webui", "challenge": "", "action": "delete", "target": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixtur
CASE=replay METHOD=POST PATH=/verify HTTP=429 BODY={"ok": false, "error": "TOTP replay rejected"}
CASE=verify_repeat METHOD=POST PATH=/verify HTTP=404 BODY={"ok": false, "error": "pending request not found or expired"}
CASE=trash_undo METHOD=POST PATH=/trash/undo HTTP=200 BODY={"ok": true, "restored": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixture-1rbzm5au\\shared\\fixture-delete.txt", "id": "c8988fbd30c3"}
CASE=verify_after_undo METHOD=POST PATH=/verify HTTP=404 BODY={"ok": false, "error": "pending request not found or expired"}
RUNTIME_FIXTURE_OK
EVIDENCE=D:\qq苏瑾言大肥鱼\public-release\quality\artifacts\runtime_fixture\http_statuses.json
EXIT_CODE=0
```
## Fixture HTTP evidence
- quality/artifacts/runtime_fixture/http_statuses.json
- quality/artifacts/runtime_fixture/audit_tail.jsonl
- quality/artifacts/runtime_fixture/broker_process.txt

## Static Analysis Coverage
- mypy: 53/53 Python source files under tools/webui/installer; excludes tests, webui/.venv and caches.
- pyright: 53/53 Python source files under tools/webui/installer; excludes the same directories.
- PSSA: 88/89 runtime PowerShell files under installer/tools/webui; excludes tests and artifacts.
- vulture: 53/53 production Python files with the documented 67-entry dynamic-entry whitelist.

## FIXED_THIS_ROUND
- 修复 Broker 鉴权顺序：/pending 缺少 token 现在直接返回 403。
- 修复 TOTP replay：已消费验证码现在返回 HTTP 429。
- 新增真实 fixture、HTTP 证据、测试冻结和 mutation 检查。
- 修复 PSSA 空 catch 和自动变量覆盖。
- D5 四文件签名/verify 已实现；D4 由人类在管理员权限下手动完成，根路径 1125B 旧签名器已移至 .deleted-20261105。
- tools/sign_release.py、tools/verify_release.py、tools/Run-ReleasePipeline.ps1 已纳入 test_guard.CRITICAL，V3 门禁信任根漏洞已修补。

## NOT_FIXED_THIS_ROUND
- 真实 ACL/DPAPI/WFP/卸载残留仍需干净 VM 验证。
- PSSA 未覆盖测试脚本全规则，测试脚本只做语法解析。
- vulture 白名单仍有动态入口人工审查风险。

## CANDIDATE mode
Static, comment and documentation gates passed. Quality/chaos/VM evidence is NOT claimed for this candidate.
## build candidate
```text
packaging gates OK
code comments gate OK
docs consistency gate OK
text hygiene OK
wrote D:\qq苏瑾言大肥鱼\public-release-v1.6.3.zip
version=1.6.3 files=381 bytes=51459838
sha256=42f1a0440671e12ce016ef927611fd659c5dc392a9bc6f47623b0c848b3dcc34
EXIT_CODE=0
```
- Candidate Zip SHA256: 42F1A0440671E12CE016EF927611FD659C5DC392A9BC6F47623B0C848B3DCC34
