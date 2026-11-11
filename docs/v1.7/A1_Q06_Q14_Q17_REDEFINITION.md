# A1 Q06/Q14/Q17 重定义（owner approved 2026-11-11）

## 决定

Owner 选择 **D2**：

- High tier 不恢复 astrbot/snowluma
- High tier 不内置 AgentRuntime
- Q06/Q14/Q17 不再要求 `CyberButlerAgentRuntime` service
- 改为测试 CBS 自身边界
- 保留 26/26 口径
- 旧 Q06 的 `BLOCKED:SERVICE_NOT_FOUND` 保留为历史记录，不直接改成 PASS

## Q06：CBS 服务账户边界

必须验证：

1. `CyberButlerSvc` 本地账户存在且启用
2. 不属于 Administrators
3. 拥有 `SeServiceLogonRight`
4. `C:\CyberButler` 数据目录 ACL 包含该服务账户 ACE
5. CBS 不持有 `CyberButlerAgentRuntime` service / identity
6. AgentRuntime 明确为外部组件

## Q14：Broker token / WebUI 权限边界

必须验证：

1. `broker_token.txt` 不可被普通 Users 读取
2. 无 token 的 `/request` 被拒绝（401/403）
3. 错误 token 的 `/request` 被拒绝（401/403）
4. Broker/WebUI 只监听 loopback
5. 不再只检查 `CyberButlerAgentRuntime` service 存在

## Q17：Broker 中断/恢复

必须验证：

1. Broker 初始 `/health` = 200
2. 停止 `Cyber-Butler Broker` 后 health 不可用
3. 重新启动后 health 恢复 200
4. 只有一个 Broker 计划任务，无 orphan
5. 审计目录/日志存在
6. 不要求 `CyberButlerAgentRuntime` service

## 当前 A1 状态（重定义后）

```text
Q05 PASS
Q07 PASS
Q08 PASS
Q09 PASS

Q06  BLOCKED — SE_SERVICE_LOGON_RIGHT_MISSING（待复核）
Q14  BLOCKED — Broker 未运行，no-token 请求无法验证
Q17  BLOCKED — Broker 恢复 health=0

Q10–Q13, Q15–Q16 未补齐
26/26 NOT GENERATED
A1 = A1_PRODUCT_INSTALLED_QA_PARTIAL
```

重定义不产生 PASS；只有实际测试通过才更新。
