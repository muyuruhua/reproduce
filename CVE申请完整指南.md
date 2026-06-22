# CVE 申请完整指南

---

## 一、CVE 是什么

CVE = Common Vulnerabilities and Exposures，由 MITRE 维护，给每个公开漏洞分配唯一编号 `CVE-YYYY-NNNNN`。拿到编号后才能提交 NVD 评分。

> CVE 不是安全公告，只是一个编号 + 一段描述。

---

## 二、谁来分配 CVE — CNA 选择

CNA = CVE Numbering Authority，你不能自己编编号，必须通过 CNA 申请。

| 方式 | 难度 | 速度 | 说明 |
|------|:---:|:---:|------|
| **GitHub Security Advisory** ★★★★★ | 低 | 快(几小时~天) | 在 GitHub repo 提交，GitHub 是 CNA |
| MITRE CVE Request Form ★★★★ | 中 | 中(几天~周) | https://cveform.mitre.org/ |
| 上游厂商 | 不定 | 慢 | 联系 bftpd/ProFTPD 等项目方 |

**推荐用 GitHub Security Advisory**：浏览器打开 `https://github.com/muyuruhua/reproduce/security` → "New draft security advisory"。

---

## 三、哪些漏洞值得申请 CVE

6,613 行 Excel ＝ 约 54 种漏洞类型。不是每种都需要单独 CVE。

| 优先级 | 漏洞 | 理由 |
|:---:|------|------|
| P0 | **proftpd CRLF注入 (417条)** | ProFTPD 首个 CRLF注入公开发现，无已知CVE覆盖 |
| P0 | **proftpd 堆UAF (62条)** | 新UAF位置，不同于 CVE-2020-9273 |
| P0 | **mosquitto Will消息写$SYS (50条)** | 全新漏洞模式，无已知CVE |
| P1 | **bftpd 堆溢出 (500条)** | 可远程触发、无需认证、对标 CVE-2025-11947 |
| P1 | **exim SMTP走私 (346条)** | CVE-2023-51766 在 4.96 的新攻击向量 |
| P1 | **live555 堆UAF (72条)** | 对标 CVE-2023-37117，ASAN完整调用栈 |
| P2 | **kamailio 堆破坏 (68条)** | 对标 CVE-2020-27507 |
| P2 | **各FTP目标 CRLF注入** | 跨目标同类漏洞，可合并或分开申请 |
| P2 | **mosquitto 会话碰撞 (9条)** | MQTT协议级新模式 |

---

## 四、CVE 申请必须包含的材料

1. **漏洞描述**：受影响产品版本、漏洞类型(CWE)、攻击向量、影响
2. **复现步骤** ★ 最关键：审核员能独立复现
3. **根因分析**（可选但加分）：涉及的代码路径
4. **时间线**（如已联系厂商）

---

## 五、完整的 CVE 申请文本模板

以 proftpd CRLF 注入为例，可以直接复制到 GitHub Security Advisory：

---

**Title**: ProFTPD 1.3.9rc1 — CRLF Injection in FTP Command Arguments (CWE-93)

**Severity**: High

**CWE**: CWE-93 (Improper Neutralization of CRLF Sequences)

**Product**: ProFTPD 1.3.9rc1

**Vendor**: The ProFTPD Project (http://www.proftpd.org/)

**Description**:

ProFTPD 1.3.9rc1 contains a CRLF injection vulnerability in its FTP command
processing. When handling malformed FTP commands with embedded CRLF sequences
in command arguments, the server fails to properly neutralize these control
characters. This allows an unauthenticated remote attacker to inject and smuggle
additional FTP commands, bypassing the intended command processing flow.

This is the first known CRLF injection discovery in ProFTPD. No existing CVE
covers this vulnerability pattern.

**Impact**:
- Command smuggling: attacker-injected commands executed by server
- Authentication bypass: smuggled commands bypass normal auth state machine
- Potential for unauthorized file access

**CVSS 3.1 Score**: 8.1 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N)

**Reproduction Steps**:

```
1. Clone the reproduction package:
   git clone https://github.com/muyuruhua/reproduce
   cd reproduce

2. Import Docker images:
   for f in docker_images/*.tar.gz; do docker load -i "$f"; done

3. Run the reproduction command:
   bash scripts/reproduce_from_excel.sh proftpd viol 0x0020

4. Expected output:
   [HIGH] CRLF_INJECTION: CRLF injection in FTP command: ...
   [CONFIRMED] N oracle violation(s) verified
```

The full reproduction environment is self-contained in the Docker image
(proftpd:latest, compiled with ASAN). The seed file is extracted automatically
from the fuzzing results tarball. No external dependencies required.

**Discovery Method**:
Automated via AFLNet + ChatAFL-Opt hybrid fuzzing (LLM-guided network protocol
fuzzer). 240 hours of fuzzing across 10 ablation groups.

**Fix Recommendation**:
Sanitize CR (%0d) and LF (%0a) characters in FTP command arguments before
processing. Reject commands containing embedded line terminators in parameter
fields.

**Credits**: [Your Name] using ChatAFL-Master framework

---

## 六、操作步骤

### Step 1: 生成证据日志

```bash
# 每条 CVE 一个日志文件，作为申请附件
bash scripts/reproduce_from_excel.sh proftpd viol 0x0020 | tee /tmp/cve_proftpd_crlf.log
bash scripts/reproduce_from_excel.sh proftpd crash         | tee /tmp/cve_proftpd_uaf.log
bash scripts/reproduce_from_excel.sh bftpd crash           | tee /tmp/cve_bftpd_heap.log
bash scripts/reproduce_from_excel.sh exim viol 0x04e0      | tee /tmp/cve_exim_smuggling.log
bash scripts/reproduce_from_excel.sh mosquitto-v2.0.18 viol 0x028e | tee /tmp/cve_mosquitto_acl.log
bash scripts/reproduce_from_excel.sh live555 crash         | tee /tmp/cve_live555_uaf.log
```

### Step 2: 打开 GitHub Security Advisory

```
https://github.com/muyuruhua/reproduce/security
→ "New draft security advisory"
→ 填入模板内容
→ 提交
```

### Step 3: 等待 CVE 分配

GitHub 自动向 MITRE 请求 CVE 编号。通常几小时到几天。

### Step 4: 收到编号后

- 可选：通知厂商（如 bftpd 作者、ProFTPD 团队）
- 可选：申请 NVD 评分（https://nvd.nist.gov/）

---

## 七、各目标的复现命令汇总

| 目标 | 漏洞 | 命令 |
|------|------|------|
| bftpd | 堆溢出 (CWE-122) | `bash scripts/reproduce_from_excel.sh bftpd crash` |
| bftpd | CRLF注入 (CWE-93) | `bash scripts/reproduce_from_excel.sh bftpd viol 0x0020` |
| bftpd | 信息泄露 (CWE-200) | `bash scripts/reproduce_from_excel.sh bftpd viol 0x0008` |
| proftpd | 堆UAF (CWE-416) | `bash scripts/reproduce_from_excel.sh proftpd crash` |
| proftpd | CRLF注入 (CWE-93) | `bash scripts/reproduce_from_excel.sh proftpd viol 0x0020` |
| exim | SMTP走私 (CWE-93) | `bash scripts/reproduce_from_excel.sh exim viol 0x04e0` |
| live555 | 堆UAF (CWE-416) | `bash scripts/reproduce_from_excel.sh live555 crash` |
| mosquitto | ACL绕过+会话劫持 | `bash scripts/reproduce_from_excel.sh mosquitto-v2.0.18 viol 0x028e` |
| kamailio | 堆破坏 (CWE-122) | `bash scripts/reproduce_from_excel.sh kamailio crash` |
| pure-ftpd | CRLF注入 (CWE-93) | `bash scripts/reproduce_from_excel.sh pure-ftpd viol 0x0020` |
| lightftp | FTP Bounce (CWE-441) | `bash scripts/reproduce_from_excel.sh lightftp viol 0x0100` |
| lighttpd1 | HTTP走私 (CWE-444) | `bash scripts/reproduce_from_excel.sh lighttpd1 viol 0x0408` |

---

## 八、常见问题

**Q: 6,613 条要申请 6,613 个 CVE 吗？**

不用。每条 CVE 对应一个漏洞类型。约 10-15 条值得独立申请。

**Q: 审核员会自己复现吗？**

会。`reproduce/` 目录就是为此准备的——审核员执行同一命令，看到同样的 `CRASH DETECTED` / `CONFIRMED`。

**Q: 需要先联系厂商吗？**

不是必需的。可以先申请 CVE 编号，再通知厂商。

**Q: 多久能拿到 CVE 编号？**

GitHub Advisory: 几小时到几天。MITRE 直接: 几天到几周。
