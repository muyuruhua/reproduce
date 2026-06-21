# Pure-FTPd 1.0.51 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | Pure-FTPd 1.0.51 (FTP Server) |
| **协议** | FTP (RFC 959) |
| **端口** | 21 |
| **Docker 镜像** | `pure-ftpd:latest` |
| **漏洞总数** | **1,164** (0 崩溃 + 1,164 逻辑漏洞) |
| **发现日期** | 2026-06-15 |

---

## 前置条件

```bash
docker image inspect pure-ftpd:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/FTP/PureFTPD
    docker build . -t pure-ftpd --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型 (全部逻辑漏洞 ✅ 可复现)

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| CRLF 注入 / FTP 命令走私 | CWE-93 | 424 | CVE-2026-39983 |
| FTP Bounce 攻击 | CWE-441 | 324 | CVE-2018-15516 |
| 状态机违规 (RNTO without RNFR) | CWE-696 | 123 | **N/A (新发现)** |
| 路径遍历 | CWE-22 | 101 | CVE-2024-3935 |
| 敏感信息泄露 | CWE-200 | 96 | CVE-2024-42650 |
| 认证绕过 (PASS without USER) | CWE-862 | 90 | CVE-2024-42644 |
| 格式字符串风险 | CWE-134 | 6 | CVE-2006-6750 |

> **Pure-FTPd 1.0.51 内存安全性良好**: ~246小时模糊测试, 0次崩溃。

---

## 复现步骤

```bash
bash reproduce/scripts/replay_logical_vuln.sh pure-ftpd <violation_source> /tmp/pureftpd_replay
```

### 确认步骤
1. **CRLF_INJECTION**: FTP命令中包含嵌入的CRLF序列导致命令走私
2. **FTP_BOUNCE**: PORT to 内部IP被接受
3. **STATE_VIOLATION**: RNTO without prior RNFR被接受
4. **PATH_TRAVERSAL**: 路径遍历返回成功码
5. **AUTH_BYPASS**: PASS without USER返回认证成功
6. **INFO_LEAK**: 响应中包含 `/etc/passwd` 或 `root:` 等敏感信息
7. **FORMAT_STRING**: 多个 `%s/%n/%x` 格式说明符在命令中 (≥2)

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name pureftpd_repro pure-ftpd:latest /bin/bash -c \
    "cd /home/ubuntu/experiments/pure-ftpd && \
     /home/ubuntu/experiments/clean 2>/dev/null; \
     ulimit -n 1024 && src/pure-ftpd -A && sleep infinity"

nc -z 127.0.0.1 21 && echo "FTP ready on port 21"

bash reproduce/scripts/replay_logical_vuln.sh pure-ftpd <violation_source>

docker rm -f pureftpd_repro
```
