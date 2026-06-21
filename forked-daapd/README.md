# forked-daapd 27.2 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | forked-daapd 27.2 (owntone-server, DAAP/HTTP media server) |
| **协议** | DAAP/HTTP |
| **端口** | 3689 |
| **Docker 镜像** | `forked-daapd:latest` |
| **漏洞总数** | **199** (39 崩溃 + 160 逻辑漏洞) |
| **发现日期** | 2026-06-07 |

---

## 前置条件

```bash
docker image inspect forked-daapd:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/DAAP/forked-daapd
    docker build . -t forked-daapd --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| 内存破坏 (heap/stack) | CWE-122/CWE-416 | 39 | CVE-2025-44560 |
| DoS/资源耗尽 (hang/timeout) | CWE-400 | 107 | CVE-2025-63647 |
| HTTP 请求走私 (多 Content-Length) | CWE-444 | 27 | CVE-2023-25690 |
| CRLF 注入/响应分裂 | CWE-113 | 21 | CVE-2023-38709 |
| 认证绕过 (%00 null-byte) | CWE-306 | 4 | CVE-2017-3167 |
| 路径遍历 | CWE-22 | 1 | CVE-2021-42013 |

> **注意**: 崩溃仅在 AFLNet persistent mode 下可复现（需要特定堆状态），Docker standalone 重放可能不会触发。

---

## 漏洞类型 1: 内存破坏 — 39 个 (需 AFL 环境)

### 复现步骤
这些崩溃需在原始 AFL fuzzer 环境中复现，因为 ASAN 堆破坏依赖 persistent mode fork-server 状态累积。
```bash
# 在原始 AFL fuzzer 工作目录中执行
aflnet-replay <crash_seed> HTTP 3689
```

## 漏洞类型 2: HTTP 逻辑漏洞 — 160 个 (Docker 可复现)

### 复现步骤
```bash
bash reproduce/scripts/replay_logical_vuln.sh forked-daapd <violation_source> /tmp/daapd_logical_replay
```

### 确认步骤
- **DoS**: 服务器响应超时或无响应（需与正常baseline对比）
- **SMUGGLING**: 多 Content-Length 头导致请求走私（前后端解析差异）
- **INJECTION**: CRLF 序列触发响应分裂
- **PATH_TRAVERSAL**: `../` 或 `%2e%2e/` 路径被接受

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name daapd_repro forked-daapd:latest /bin/bash -c \
    "sudo service dbus start 2>/dev/null; \
     sudo service avahi-daemon start 2>/dev/null; \
     HOME=/home/ubuntu /home/ubuntu/experiments/forked-daapd/src/forked-daapd \
       -d 0 -c /home/ubuntu/experiments/forked-daapd.conf -f && sleep infinity"

nc -z 127.0.0.1 3689 && echo "DAAP ready on port 3689"

bash reproduce/scripts/replay_logical_vuln.sh forked-daapd <violation_source>

docker rm -f daapd_repro
```
