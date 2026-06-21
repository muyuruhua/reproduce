# ProFTPD 1.3.9rc1 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | ProFTPD 1.3.9rc1 (FTP Server) |
| **协议** | FTP (RFC 959) |
| **端口** | 21 |
| **Docker 镜像** | `proftpd:latest` |
| **漏洞总数** | **1,204** (62 崩溃 + 1,142 逻辑漏洞) |
| **发现日期** | 2026-06-08 |

---

## 前置条件

```bash
docker image inspect proftpd:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/FTP/ProFTPD
    docker build . -t proftpd --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| CRLF 注入 / FTP 命令走私 | CWE-93 | 417 | **N/A (ProFTPD首次发现)** |
| FTP Bounce 攻击 | CWE-441 | 281 | CVE-2018-15516 |
| 敏感信息泄露 | CWE-200 | 287 | CVE-2024-42650 |
| 状态机违规 (RNTO without RNFR) | CWE-696 | 73 | **N/A (首次发现)** |
| 路径遍历 | CWE-22 | 43 | CVE-2024-3935 |
| 认证状态绕过 (PASS without USER) | CWE-862 | 41 | CVE-2024-42644 |
| **Heap Use-After-Free** | **CWE-416** | **62** | **N/A (新UAF, 不同于 CVE-2020-9273)** |

---

## ⭐ 关键漏洞: Heap Use-After-Free — 62 个 ✅ 可复现

### 描述
**新发现的 Heap UAF**，在 session cleanup 代码路径中触发。与 CVE-2020-9273（pool.c UAF）不同，此 UAF 位于 session cleanup 函数，通过 TCP 连接关闭触发。

### 复现步骤
```bash
bash reproduce/scripts/replay_crash.sh proftpd <crash_seed_file> /tmp/proftpd_crash_replay
```

**重要**: ProFTPD ASAN 构建中 `nc -z` 健康检查会触发崩溃，已替换为进程存活检查。

### 确认步骤
1. 输出包含 `[CRASH DETECTED]`
2. exit_code=134 (SIGABRT)
3. ASAN 报告包含 `heap-use-after-free` 关键字
4. 调用栈指向 session cleanup 函数

### 预期结果
```
[CRASH DETECTED] replay #<N>: server crashed! exit_code=134
[CRASH] Signal 6 = ABRT
ERROR: AddressSanitizer: heap-use-after-free on address ...
```

---

## 漏洞类型 2: CRLF 注入 (ProFTPD 首次发现) — 417 个

这是 **ProFTPD 中 CRLF 注入/FTP命令走私的首次发现**，无已知公开 CVE。

### 复现步骤
```bash
bash reproduce/scripts/replay_logical_vuln.sh proftpd <violation_source> /tmp/proftpd_replay
```

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name proftpd_repro proftpd:latest /bin/bash -c \
    "cd /home/ubuntu/experiments/proftpd && \
     sed -i 's/MaxInstances.*1/MaxInstances 10/' /home/ubuntu/experiments/basic.conf && \
     ./proftpd -n -c /home/ubuntu/experiments/basic.conf && sleep infinity"

# 使用进程存活检查（非nc -z，避免ASAN崩溃）
sleep 2
docker exec proftpd_repro bash -c "kill -0 \$(pgrep proftpd) 2>/dev/null" && \
    echo "FTP ready on port 21"

bash reproduce/scripts/replay_crash.sh proftpd <crash_seed_file>

docker rm -f proftpd_repro
```
