# LIVE555 RTSP Server — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | LIVE555 RTSP Server (testOnDemandRTSPServer) |
| **协议** | RTSP (RFC 2326) |
| **端口** | 8554 |
| **Docker 镜像** | `live555:latest` |
| **漏洞总数** | **370** (72 崩溃 + 298 逻辑漏洞) |
| **发现日期** | 2026-06-08 |

---

## 前置条件

```bash
docker image inspect live555:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/RTSP/Live555
    docker build . -t live555 --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| 重复SETUP (UAF/double-free风险) | CWE-416 | 153 | CVE-2019-7314 |
| Transport header 过长 (栈溢出) | CWE-121 | 43 | CVE-2018-4013 |
| 超大 CSeq header | CWE-252 | 31 | CVE-2019-7314 |
| transport port=0 (DoS) | CWE-252 | 29 | CVE-2019-6256 |
| PLAY before SETUP (状态违规) | CWE-696 | 29 | CVE-2021-38382 |
| RECORD before SETUP (状态违规) | CWE-696 | 13 | CVE-2018-4013 |
| Heap UAF (SETUP处理) | CWE-416 | 72 | **CVE-2023-37117** |

> **注意**: 崩溃 (UAF) 仅限 AFLNet persistent mode 可复现。Docker standalone 重放需要 gdb 附加。

---

## 复现步骤

```bash
# 逻辑漏洞复现
bash reproduce/scripts/replay_logical_vuln.sh live555 <violation_source> /tmp/live555_replay

# 崩溃复现 (可能需要多次尝试)
bash reproduce/scripts/replay_crash.sh live555 <crash_seed_file> /tmp/live555_crash_replay
```

### 确认步骤
- **DUPLICATE_SETUP**: 相同URL的重复SETUP被接受（UAF风险）
- **STATE_VIOLATION**: PLAY/RECORD在SETUP之前被接受
- **DOS_PORT_ZERO**: client_port=0被接受
- **BUFFER_OVERFLOW**: 超长Transport/CSeq头被接受(>500B)

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name live555_repro live555:latest /bin/bash -c \
    "cd /home/ubuntu/experiments/live/testProgs && \
     ./testOnDemandRTSPServer 8554 && sleep infinity"

nc -z 127.0.0.1 8554 && echo "RTSP ready on port 8554"

bash reproduce/scripts/replay_logical_vuln.sh live555 <violation_source>

docker rm -f live555_repro
```
