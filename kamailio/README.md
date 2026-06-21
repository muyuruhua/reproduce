# Kamailio 5.8.0-dev0 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | Kamailio 5.8.0-dev0 (SIP Server) |
| **协议** | SIP (RFC 3261, UDP) |
| **端口** | 5060 (UDP) |
| **Docker 镜像** | `kamailio:latest` |
| **漏洞总数** | **343** (68 崩溃 + 275 逻辑漏洞) |
| **发现日期** | 2026-06-07 |

---

## 前置条件

```bash
docker image inspect kamailio:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/SIP/Kamailio
    docker build . -t kamailio --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| Heap 内存破坏 (SIGABRT) | CWE-122 | 68 | **CVE-2020-27507** (类似) |
| SIP 注入 (SQL注入模式) | CWE-89 | 48 | CVE-2008-6573 |
| 状态违规 + 注入 (复合) | CWE-696/CWE-89 | 30 | 混合 CVEs |
| DoS / Via 头放大攻击 | CWE-770 | 27 | CVE-2020-28361 |
| 认证绕过 (INVITE without auth) | CWE-862 | 25 | CVE-2021-37624 |
| 状态违规 (ACK without INVITE) | CWE-696 | 22 | CVE-2023-49323 |

---

## 漏洞类型 1: Heap 内存破坏 — 68 个 ✅ 可复现

### 描述
ASAN 检测到的堆内存破坏，由 2 条紧凑 SIP 消息触发（短种子）。3/3 测试种子 100% 复现。

### 复现步骤
```bash
bash reproduce/scripts/replay_crash.sh kamailio <crash_seed_file> /tmp/kamailio_crash_replay
```

### 确认步骤
1. 输出包含 `[CRASH DETECTED]`
2. exit_code=134 (SIGABRT)
3. ASAN 报告显示 heap-buffer-overflow

## 漏洞类型 2: SIP 逻辑漏洞 — 275 个

### 复现步骤
```bash
bash reproduce/scripts/replay_logical_vuln.sh kamailio <violation_source> /tmp/kamailio_replay
```

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -e KAMAILIO_MODULES=src/modules -e KAMAILIO_RUNTIME_DIR=runtime_dir \
    -d --name kamailio_repro kamailio:latest /bin/bash -c \
    "cd /home/ubuntu/experiments/kamailio && mkdir -p runtime_dir && \
     ./src/kamailio -f /home/ubuntu/experiments/kamailio-basic.cfg \
       -L src/modules -Y runtime_dir -n 1 -D -E && sleep infinity"

# SIP 使用 UDP，用 echo >/dev/udp 验证
echo >/dev/udp/127.0.0.1/5060 2>/dev/null && echo "SIP ready on UDP 5060"

bash reproduce/scripts/replay_crash.sh kamailio <seed_file>

docker rm -f kamailio_repro
```
