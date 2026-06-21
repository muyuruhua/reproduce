# lighttpd 1.4.72-devel — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | lighttpd 1.4.72-devel (HTTP Server) |
| **协议** | HTTP/1.1 |
| **端口** | 8080 |
| **Docker 镜像** | `lighttpd1:latest` |
| **漏洞总数** | **125** (0 崩溃 + 125 逻辑漏洞) |
| **发现日期** | 2026-06-07 |

---

## 前置条件

```bash
docker image inspect lighttpd1:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/HTTP/Lighttpd1
    docker build . -t lighttpd1 --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| 路径遍历 | CWE-22 | 53 | CVE-2018-19052 |
| HTTP 请求走私 (CL Desync) | CWE-444 | 49 | CVE-2023-25690 |
| CRLF 注入 / 响应分裂 | CWE-113 | 10 | CVE-2023-38709 |
| CL+TE 请求走私 | CWE-444 | 7 | CVE-2023-44487 |
| 认证绕过 (URL编码) | CWE-306 | 3 | CVE-2008-4359 |
| 双重编码路径遍历 | CWE-22 | 1 | CVE-2021-42013 |

> **lighttpd 1.4.72-devel 内存安全性良好**: ~53M 次执行，0 次崩溃。

---

## 复现步骤

```bash
bash reproduce/scripts/replay_logical_vuln.sh lighttpd1 <violation_source> /tmp/lighttpd1_replay
```

### 确认步骤
1. **PATH_TRAVERSAL**: `/../../../etc/passwd` 类路径返回 200（非403/404）
2. **SMUGGLING**: 多个 Content-Length 头导致请求走私
3. **CL+TE Smuggling**: Content-Length 和 Transfer-Encoding 同时存在
4. **INJECTION**: 响应中包含注入的HTTP头（响应分裂）
5. **AUTH_BYPASS**: URL-encoded认证信息绕过访问控制

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name lighttpd1_repro lighttpd1:latest /bin/bash -c \
    "cd /home/ubuntu/experiments/lighttpd1 && \
     ./src/lighttpd -D -f /home/ubuntu/experiments/lighttpd.conf \
       -m ./src/.libs && sleep infinity"

nc -z 127.0.0.1 8080 && echo "HTTP ready on port 8080"

bash reproduce/scripts/replay_logical_vuln.sh lighttpd1 <violation_source>

docker rm -f lighttpd1_repro
```
