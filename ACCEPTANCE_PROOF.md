# ACCEPTANCE_PROOF

- Executed: 2026-11-05T17:06:46.0798233Z
- Host: HYPERPC
- Nonce: A-READY-20261106-0110
- Acceptance script SHA256 (start): 4BD945E11273D87E49945E7CD95E1BDE2A95227C9CFEB91FBA099E5174D7480C
- MAC: 00-15-5D-01-6F-00
- VERSION: 1.6.3
- Package SHA256: 2CAA60B88FE9E65B2F8B818D967D91593A4B1491CBD0EA15E0013AF15327ACA8
- Install report: success

## icacls broker_token.txt
```text
C:\CyberButler\tools\broker_token.txt hyperpc\PAN:(R)
                                      BUILTIN\Administrators:(F)
                                      hyperpc\CyberButlerSvc:(R)
                                      NT AUTHORITY\SYSTEM:(F)

已成功处理 1 个文件; 处理 0 个文件时失败
```
- Token readback length: 43

## Win32_Process evidence
- PID=13560 NAME=CyberButlerLauncher.exe CMD="C:\CyberButler\tools\CyberButlerLauncher.exe" --exe "C:\CyberButler\webui\.venv\Scripts\python.exe" --workdir "C:\CyberButler\tools" --args "broker.py" --hidden --wait --log "C:\CyberButler\tools\logs\broker-startup.log"
- PID=14808 NAME=python.exe CMD="C:\CyberButler\webui\.venv\Scripts\python.exe" broker.py
- PID=16068 NAME=python.exe CMD="C:\CyberButler\webui\.venv\Scripts\python.exe" broker.py
- PID=11888 NAME=CyberButlerLauncher.exe CMD="C:\CyberButler\tools\CyberButlerLauncher.exe" --exe "powershell.exe" --workdir "C:\CyberButler\webui" --args "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"start-services.ps1\"" --hidden --wait --log "C:\CyberButler\webui\data\webui-service.log"
- PID=10148 NAME=pythonw.exe CMD="C:\CyberButler\webui\.venv\Scripts\pythonw.exe" otp_mailer.py 
- PID=652 NAME=pythonw.exe CMD="C:\CyberButler\webui\.venv\Scripts\pythonw.exe" otp_mailer.py 
- PID=9016 NAME=pythonw.exe CMD="C:\CyberButler\webui\.venv\Scripts\pythonw.exe" run.py 
- PID=14560 NAME=pythonw.exe CMD="C:\CyberButler\webui\.venv\Scripts\pythonw.exe" run.py 

## Negative test: wrong TOTP must be rejected
REQUEST RAW:
```text
{"ok": true, "status": "requires_totp", "id": "ebed55d1e742", "channel": "webui", "challenge": "", "action": "delete", "target": "C:\\CyberButler\\workspace\\negative-totp.txt"}
HTTP_STATUS:200
EXIT:0
```
VERIFY RAW:
```text
{"ok": false, "error": "invalid verification code", "attempts": 1}
HTTP_STATUS:403
EXIT:0
```
FORGED TOKEN RAW:
```text
{"ok": false, "error": "unauthorized"}
HTTP_STATUS:403
EXIT:0
```
WRONG_PATH RAW:
```text
{"ok": false, "error": "target is not allowed by broker policy"}
HTTP_STATUS:403
EXIT:0
```

## Positive TOTP and two-stage undo
REQUEST RAW:
```text
{"ok": true, "status": "requires_totp", "id": "96a4ac88c489", "channel": "webui", "challenge": "", "action": "delete", "target": "C:\\CyberButler\\workspace\\positive-totp.txt"}
HTTP_STATUS:200
EXIT:0
```
positive VERIFY RAW (attempt 1):
```text
{"ok": true, "id": "96a4ac88c489", "result": "文件已移入两阶段暂存回收站，10 分钟内可撤回：96a4ac88c489", "undo_available": true, "trash_id": "96a4ac88c489", "undo_expires_at": "2026-11-05T17:17:06+00:00", "undo_expires_epoch": 1793899026.6012156}
HTTP_STATUS:200
EXIT:0
```
VERIFY RAW:
```text
{"ok": true, "id": "96a4ac88c489", "result": "文件已移入两阶段暂存回收站，10 分钟内可撤回：96a4ac88c489", "undo_available": true, "trash_id": "96a4ac88c489", "undo_expires_at": "2026-11-05T17:17:06+00:00", "undo_expires_epoch": 1793899026.6012156}
HTTP_STATUS:200
EXIT:0
```
TRASH RAW:
```text
{"ok": true, "items": [{"id": "96a4ac88c489", "original_path": "C:\\CyberButler\\workspace\\positive-totp.txt", "expires_at": "2026-11-05T17:17:06+00:00", "expires_epoch": 1793899026.6012156, "size": 13}]}
HTTP_STATUS:200
EXIT:0
```
UNDO RAW:
```text
{"ok": true, "restored": "C:\\CyberButler\\workspace\\positive-totp.txt", "id": "96a4ac88c489"}
HTTP_STATUS:200
EXIT:0
```

## audit.jsonl evidence
```jsonl
{"at": "2026-11-06T01:06:48", "id": "ebed55d1e742", "action": "delete", "target": "C:\\CyberButler\\workspace\\negative-totp.txt", "ok": false, "result": "invalid TOTP or recovery code", "attempts": 1}
{"at": "2026-11-06T01:07:06", "id": "96a4ac88c489", "action": "delete", "target": "C:\\CyberButler\\workspace\\positive-totp.txt", "ok": true, "result": "文件已移入两阶段暂存回收站，10 分钟内可撤回：96a4ac88c489", "code_type": "totp", "bypass_issued": false, "bypass_ttl": 0, "scoped_issued": false, "scoped_ttl": 0}
{"at": "2026-11-06T01:07:06", "id": "96a4ac88c489", "action": "trash_undo", "target": "C:\\CyberButler\\workspace\\positive-totp.txt", "ok": true, "result": "two-stage delete restored by owner"}
```

## Capacity breaker
capacity VERIFY RAW (attempt 1):
```text
{"ok": false, "error": "TOTP replay rejected"}
HTTP_STATUS:429
EXIT:0
```
capacity TOTP replay guard: HTTP 429; waiting 35 seconds for a fresh code
capacity VERIFY RAW (attempt 2):
```text
{"ok": false, "id": "926f33c3945b", "result": "暂存区容量熔断，删除已拦截；没有移动任何文件。trash staging byte quota exceeded: 524288000 bytes"}
HTTP_STATUS:500
EXIT:0
```
CAPACITY RAW:
```text
{"ok": false, "id": "926f33c3945b", "result": "暂存区容量熔断，删除已拦截；没有移动任何文件。trash staging byte quota exceeded: 524288000 bytes"}
HTTP_STATUS:500
EXIT:0
```
- Acceptance script SHA256 (end): 4BD945E11273D87E49945E7CD95E1BDE2A95227C9CFEB91FBA099E5174D7480C

## Exit codes / checks
```text
install_report=True
icacls_token=True
token_readback=True
process_evidence=True
negative_403=True
negative_token=True
safe_after_negative=True
negative_path=True
positive_totp=True
undo=True
audit_evidence=True
capacity_block=True
script_immutable=True
OVERALL=PASS
```

**Overall: PASS**
