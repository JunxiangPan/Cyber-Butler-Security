# BUILD_REPORT

ChallengeCode: A-READY-20261105-1750
- Generated: 2026-11-05T09:32:42.7525262Z
- Host: PCVP
- Pipeline SHA256: C569DA98DAB6E34F39945FB114AA4B181F44B8018C63FD164C9D2769C8F38F16
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
PS_TESTS_PARSED=46
PS_TESTS_ERRORS=0
EXIT_CODE=0
```
## code comments (AST)
```text
CODE_COMMENT_GATE_OK
python_functions=511 missing_docstrings=0 powershell_functions=452 missing_block_comments=0
EXIT_CODE=0
```
## docs consistency
```text
DOC_CONSISTENCY_GATE_OK
EXIT_CODE=0
```
## static types/dead code/PSScriptAnalyzer
```text
===== mypy (exit 0) =====
Success: no issues found in 52 source files
===== pyright (exit 0) =====
d:\qq苏瑾言大肥鱼\public-release\installer\lib\totp_material.py
  d:\qq苏瑾言大肥鱼\public-release\installer\lib\totp_material.py:86:20 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
  d:\qq苏瑾言大肥鱼\public-release\installer\lib\totp_material.py:104:16 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
d:\qq苏瑾言大肥鱼\public-release\tools\broker.py
  d:\qq苏瑾言大肥鱼\public-release\tools\broker.py:41:12 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
d:\qq苏瑾言大肥鱼\public-release\tools\setup_totp.py
  d:\qq苏瑾言大肥鱼\public-release\tools\setup_totp.py:14:8 - warning: Import "win32crypt" could not be resolved from source (reportMissingModuleSource)
0 errors, 4 warnings, 0 informations
===== vulture (exit 0) =====

===== PSScriptAnalyzer (exit 0) =====
PSSA_FILES=81
PSSA_FINDINGS=0
STATIC_GATE_OK
EXIT_CODE=0
```
## test integrity (MANIFEST + snapshot + empty-assert AST)
```text
TEST_INTEGRITY_OK files=78
EXIT_CODE=0
```
## mutation check (real assertion inversion)
```text
TARGET D:\qq苏瑾言大肥鱼\public-release\tests\test_acl_model.py:69 test_owner_can_read_vault
ORIGINAL assert read_vault("vault", "test-user", aces).startswith("vault-")
MUTATED  assert not read_vault("vault", "test-user", aces).startswith("vault-")
EXIT=1 KILLED=True
RESTORED=True SHA256=09567d87c6828884238289dab1665b8f7901498b0c2ea875a199d2125440ab3d
TARGET D:\qq苏瑾言大肥鱼\public-release\tests\test_approval_preview.py:45 test_delete_preview_never_reads_file_content
ORIGINAL assert "do-not-print-this" not in text
MUTATED  assert not "do-not-print-this" not in text
EXIT=1 KILLED=True
RESTORED=True SHA256=6ff413ace2e2df1b9ea1e68cb76b646c1e9bf286a4ec8c2ee69706cf88cb159b
TARGET D:\qq苏瑾言大肥鱼\public-release\tests\test_approval_preview.py:77 test_external_read_warning_is_objective_not_a_verdict
ORIGINAL assert "最近读取了外部网页/文件" in text
MUTATED  assert not "最近读取了外部网页/文件" in text
EXIT=1 KILLED=True
RESTORED=True SHA256=6ff413ace2e2df1b9ea1e68cb76b646c1e9bf286a4ec8c2ee69706cf88cb159b
TARGET_1=tests\test_acl_model.py:69 assert read_vault("vault", "test-user", aces).startswith("vault-") -> assert not read_vault("vault", "test-user", aces).startswith("vault-")
TARGET_2=tests\test_approval_preview.py:45 assert "do-not-print-this" not in text -> assert not "do-not-print-this" not in text
TARGET_3=tests\test_approval_preview.py:77 assert "最近读取了外部网页/文件" in text -> assert not "最近读取了外部网页/文件" in text
ALL_TURNED_RED=True
RESTORE_OK=True
MUTATION_OK
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
CASE=request_delete METHOD=POST PATH=/request HTTP=200 BODY={"ok": true, "status": "requires_totp", "id": "81f0227bda45", "channel": "webui", "challenge": "", "action": "delete", "target": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixtur
CASE=bad_totp METHOD=POST PATH=/verify HTTP=403 BODY={"ok": false, "error": "invalid verification code", "attempts": 1}
CASE=bad_totp_second METHOD=POST PATH=/verify HTTP=403 BODY={"ok": false, "error": "invalid verification code", "attempts": 2}
CASE=good_totp METHOD=POST PATH=/verify HTTP=200 BODY={"ok": true, "id": "81f0227bda45", "result": "文件已移入两阶段暂存回收站，10 分钟内可撤回：81f0227bda45", "undo_available": true, "trash_id": "81f0227bda45", "undo_expires_at": "2026-11-05T09:43:21+00:
CASE=trash_list METHOD=GET PATH=/trash HTTP=200 BODY={"ok": true, "items": [{"id": "81f0227bda45", "original_path": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixture-qbep4a7v\\shared\\fixture-delete.txt", "expires_at": "2026-11-05
CASE=replay_request METHOD=POST PATH=/request HTTP=200 BODY={"ok": true, "status": "requires_totp", "id": "1936339b877e", "channel": "webui", "challenge": "", "action": "delete", "target": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixtur
CASE=replay METHOD=POST PATH=/verify HTTP=429 BODY={"ok": false, "error": "TOTP replay rejected"}
CASE=verify_repeat METHOD=POST PATH=/verify HTTP=404 BODY={"ok": false, "error": "pending request not found or expired"}
CASE=trash_undo METHOD=POST PATH=/trash/undo HTTP=200 BODY={"ok": true, "restored": "C:\\Users\\pjx20\\AppData\\Local\\Temp\\cbs-fixture-qbep4a7v\\shared\\fixture-delete.txt", "id": "81f0227bda45"}
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
version=1.6.3 files=372 bytes=21675832
sha256=fe69169ff2d32e832058ad548bf5bc417edaf8b5ed173afb1b2aaa1a9402a206
EXIT_CODE=0
```
- Candidate Zip SHA256: FE69169FF2D32E832058AD548BF5BC417EDAF8B5ED173AFB1B2AAA1A9402A206
