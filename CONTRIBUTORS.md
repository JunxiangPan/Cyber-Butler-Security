# Contributors

> “CBS 的架构不是由作者一个人闭门造车想出来的，而是全球开源社区共同打磨的结晶。”
>
> CBS's architecture was not invented alone behind a closed door; it is the result of the global open-source community polishing it together.

This file records the people who shaped CBS through red-team criticism, product feedback, architecture review, and community support. Names and handles are preserved as provided by the community. Contributions are described in English; Chinese community names are kept in their original form.

## International community

### Reddit — r/AI_Agents & r/SinceAI

#### u/Practical-Craft4967

CBS's most important external red-team brain. Proposed **Intent Mismatch** and **Magic Bytes file-header sniffing**. Warned against forcing the Broker to make **subjective malice judgments**, and insisted on the principle: **show objective evidence only; the human decides**.

#### u/QuanTradin

Pointed out that **ACLs cannot prevent data exfiltration** and that **WFP** is required. Asked for **logs of rejected network connections**. Proposed the **draft-area auto-release mechanism** to prevent **approval fatigue**.

#### u/Reid Marlow

Raised the critical **test-tampering risk** around `conftest.py` / `pytest.ini`. Also insisted that **Diff boundary interception must be bound to the file handle**.

#### u/Auten (Auten Team)

Explained the natural advantage of **Session 0 isolation**. Warned about **UIPI silent-failure** risk. Proposed the standard **Named Pipe + Helper** architecture.

#### u/mp3sss

Identified the **NTFS ACL blind spot**: ACLs do not cover **named pipes and the registry**. Strongly recommended **restricted tokens** to defend against **Win32 IPC attacks**.

#### u/More-Ad7285

Proposed the idea of **short-lived passwordless / automatic approval**, which led to the creation of the **Scoped Token**.

#### u/HeartMaleficent35

Strongly endorsed the **Fail-Closed** design philosophy.

#### u/rikulauttia

Provided the discussion platform in the **r/SinceAI** community.

## China ecosystem and community

### Bilibili & QQ community

#### Sandy (玩AI的Sandy君)

Well-known integration-package author. Gave fatal product-manager feedback: **“Security components must never crash the user's system or damage the integration package's reputation.”** This established CBS's baseline: **security must not break the out-of-box experience**.

#### 程序员阿江

DSH official / AI developer. Reminded us that DSH already has some built-in review features. Recommended that CBS build a **Benchmark** and provide a **DSH-specific plugin**.

#### 牧羊人AILab (DSQQ 作者)

Author of a one-click launcher. Affirmed CBS's **low-level defense value** and pointed toward future **ecosystem complementarity**.

### AgentRuntime Community — Group 18

#### 若宸

Used the **halting problem** to wake us up completely. This led us to abandon **application-layer interception** and move to **OS-level physical isolation**.

#### 墨莘子凌

Complained that **“the Bot asked me for my sudo password.”** This convinced us to **strip AI accounts of privileges**.

#### AgentRuntime Community Group 18

The wider group provided the forum in which these critiques and design debates took place.

## How to be added

Open a **Documentation / 文档纠错** issue or a pull request. Include the name or handle you want used, the platform/community, and the concrete contribution. We do not add names without permission or invent contributions.
