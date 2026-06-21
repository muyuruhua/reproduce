# Exim 4.96-221 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | Exim 4.96-221 (MTA/SMTP Server) |
| **协议** | SMTP (RFC 5321) |
| **端口** | 25 |
| **Docker 镜像** | `exim:latest` |
| **漏洞总数** | **1,050** (0 崩溃 + 1,050 逻辑漏洞) |
| **发现日期** | 2026-06-07 |

---

## 前置条件

```bash
docker image inspect exim:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/SMTP/Exim
    docker build . -t exim --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| SMTP 走私 (CRLF注入 → 命令走私) | CWE-93 | 346 | **CVE-2023-51766** |
| SMTP 开放中继 | CWE-306 | 193 | CVE-2023-42117 |
| SMTP 状态机违规 | CWE-696 | 182 | N/A (新发现) |
| SMTP 用户枚举 (VRFY/EXPN) | CWE-204 | 164 | N/A |
| SMTP 内存耗尽 (超长命令) | CWE-400 | 155 | CVE-2001-0894 |
| 格式字符串风险 | CWE-134 | 10 | CVE-2001-0894 |

> **注意**: Exim 4.96-221 在此次模糊测试中 **未产生可重放的崩溃**。165 条 crash-type 条目实际对应 0 个可重放种子。

---

## 关键漏洞复现: SMTP 走私 (CVE-2023-51766 补充向量)

### 描述
畸形 SMTP 数据中的 CRLF 注入允许攻击者走私 SMTP 命令，突破邮件服务器的安全策略。
此发现是 CVE-2023-51766 的补充攻击向量（Exim 4.96 在特定配置下仍受影响）。

### 复现步骤
```bash
bash reproduce/scripts/replay_logical_vuln.sh exim <violation_source> /tmp/exim_logical_replay
```

### 确认步骤
1. 检查服务器响应中的安全属性破坏
2. **SMTP走私确认**: 服务器将CRLF注入的内容解释为独立SMTP命令
3. **开放中继确认**: 未经AUTH的RCPT TO/DATA命令返回2xx
4. **状态违规**: RCPT TO在MAIL FROM之前被接受

### 预期结果
```
[CONFIRMED] SMUGGLING: CRLF injection in SMTP address parameter
[CONFIRMED] AUTH_BYPASS: Open relay — RCPT TO accepted without authentication
```

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name exim_repro exim:latest /bin/bash -c \
    "mkdir -p /var/lock /var/log /usr/exim/bin; \
     /home/ubuntu/experiments/clean 2>/dev/null; \
     cp /home/ubuntu/experiments/exim/src/build-Linux-x86_64/exim /usr/exim/bin/exim; \
     exim -bd -d -oX 25 -oP /var/lock/exim.pid && sleep infinity"

nc -z 127.0.0.1 25 && echo "SMTP ready on port 25"

bash reproduce/scripts/replay_logical_vuln.sh exim <violation_source>

docker rm -f exim_repro
```
