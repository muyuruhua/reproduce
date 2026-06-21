# LightFTP v2.3 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | LightFTP v2.3 (FTP Server) |
| **协议** | FTP (RFC 959) |
| **端口** | 2200 |
| **Docker 镜像** | `lightftp:latest` |
| **漏洞总数** | **291** (0 崩溃 + 291 逻辑漏洞) |
| **发现日期** | 2026-06-07 |

---

## 前置条件

```bash
docker image inspect lightftp:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/FTP/LightFTP
    docker build . -t lightftp --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型 (全部可复现 ✅)

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| FTP Bounce 攻击 | CWE-441 | 59 | CVE-2018-15516 |
| CRLF 注入 + FTP Bounce (复合) | CWE-93/CWE-441 | 47 | CVE-2026-39983 |
| CRLF 注入 | CWE-93 | 42 | CVE-2026-39983 |
| Auth Bypass + CRLF + Bounce | 复合 | 22 | 混合 |
| State Violation + FTP Bounce | CWE-696/CWE-441 | 16 | N/A |
| State Violation + CRLF | CWE-696/CWE-93 | 15 | N/A |
| 路径遍历 + 复合 | CWE-22 | ~33 | CVE-2024-3935 |
| 认证绕过 | CWE-306 | 1 | CVE-2024-42644 |

> **重要**: LightFTP v2.3 在 ~53M 次模糊测试执行中 **未产生任何内存崩溃**。
> CVE-2024-11144（竞态条件崩溃）存在但未被协议模糊测试触发。

---

## 复现步骤

```bash
# 逻辑漏洞复现 (NOTE: LightFTP 使用端口 2200!)
bash reproduce/scripts/replay_logical_vuln.sh lightftp <violation_source> /tmp/lightftp_replay
```

---

## 确认步骤
1. **FTP_BOUNCE**: PORT命令指向私有IP(127.x/10.x/192.168.x)被接受
2. **CRLF_INJECTION**: FTP命令参数中包含嵌入的CRLF序列
3. **PATH_TRAVERSAL**: `../` 路径遍历被接受（返回2xx）
4. **STATE_VIOLATION**: 非法命令序列（如RNTO without RNFR）被接受
5. **AUTH_BYPASS**: 未经认证的数据传输命令被接受

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name lightftp_repro lightftp:latest /bin/bash -c \
    "cd /home/ubuntu/experiments/LightFTP/Source/Release && \
     ./fftp fftp.conf 2200 && sleep infinity"

netstat -tlnp 2>/dev/null | grep -q ':2200 ' && echo "FTP ready on port 2200"

bash reproduce/scripts/replay_logical_vuln.sh lightftp <violation_source>

docker rm -f lightftp_repro
```
