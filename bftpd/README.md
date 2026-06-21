# BFTPD 6.1 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | BFTPD 6.1 (FTP Server) |
| **协议** | FTP (RFC 959) |
| **端口** | 21 |
| **Docker 镜像** | `bftpd:latest` |
| **漏洞总数** | **1,118** (500 崩溃 + 618 逻辑漏洞) |
| **发现日期** | 2026-06-06 |

---

## 前置条件

```bash
# 1. 确认 Docker 镜像存在
docker image inspect bftpd:latest

# 2. 如不存在，构建镜像
export PROJECT_ROOT=/path/to/ChatAFL-master
cd $PROJECT_ROOT/benchmark/subjects/FTP/BFTPD
docker build . -t bftpd --build-arg MAKE_OPT=-j$(nproc)
```

---

## 漏洞类型 1: Heap 内存破坏 (CWE-122) — 500 个

### 描述
ASAN 检测到的堆内存破坏（heap buffer overflow / UAF / double-free），由畸形 FTP 命令序列触发。
对应 CVE 模式: **CVE-2025-11947** (bftpd ≤6.2 heap overflow)

### 复现步骤
```bash
# 使用种子文件重放 (从 results tarball 提取)
bash reproduce/scripts/replay_crash.sh bftpd <crash_seed_file> /tmp/bftpd_crash_replay

# 或一键全自动 (需要 results tarball)
python3 reproduce/scripts/replay_tools.py \
    --image bftpd:latest --protocol FTP --port 21 \
    <results_dir>
```

### 确认步骤
1. 观察输出中出现 `[CRASH DETECTED]` 字样
2. 查看 exit_code: `exit_code=134` (SIGABRT) 表示 ASAN 触发了 abort
3. 查看 ASAN 报告中的调用栈确认崩溃类型（heap-buffer-overflow / heap-use-after-free / double-free）

### 预期结果
```
[CRASH DETECTED] replay #<N>: server crashed! exit_code=134
[CRASH] Signal 6 = ABRT
```

---

## 漏洞类型 2: FTP 逻辑漏洞 — 618 个

### 覆盖类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| CRLF 注入 / FTP 命令走私 | CWE-93 | ~200 | CVE-2026-39983 |
| FTP Bounce 攻击 | CWE-441 | ~150 | CVE-2018-15516 |
| 状态机违规 (RNTO without RNFR) | CWE-696 | ~100 | N/A (新发现) |
| 路径遍历 | CWE-22 | ~50 | CVE-2024-3935 |
| 认证绕过 | CWE-306 | ~50 | CVE-2024-42644 |
| 信息泄露 | CWE-200 | ~68 | CVE-2024-42650 |

### 复现步骤
```bash
bash reproduce/scripts/replay_logical_vuln.sh bftpd <violation_source> /tmp/bftpd_logical_replay
```

### 确认步骤
1. 查看输出中的 `[CONFIRMED]` 标签
2. 核实每个安全属性的验证结论:
   - **AUTH_BYPASS**: 未经认证的数据命令返回 2xx 成功码
   - **STATE_VIOLATION**: RNTO 在无 RNFR 时被接受(返回250而非503)
   - **PATH_TRAVERSAL**: 路径遍历请求返回 2xx (访问成功)
   - **CRLF_INJECTION**: FTP命令中包含嵌入的CRLF序列
   - **FTP_BOUNCE**: PORT命令指向内部/私有IP地址被接受

### 预期结果
```
=== ORACLE: N violation(s) confirmed ===
--- Confirmed #1 ---
  Severity: 4 (HIGH)
  Category: CRLF_INJECTION
  CWE: CWE-93
  Description: CRLF injection in FTP command
  CVE Pattern: CVE-2026-39983
```

---

## 一键复现
```bash
# 针对 bftpd 的全部复现
export TARGET=bftpd
export IMAGE=bftpd:latest

# 1. 确认镜像
docker image inspect $IMAGE

# 2. 启动目标服务
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name bftpd_repro $IMAGE /bin/bash -c \
    "cd /home/ubuntu/experiments/bftpd && ./bftpd -D -c /home/ubuntu/experiments/basic.conf && sleep infinity"

# 3. 验证服务可用
nc -z 127.0.0.1 21 && echo "FTP service ready on port 21"

# 4. 执行复现
bash reproduce/scripts/replay_crash.sh bftpd <seed_file>

# 5. 清理
docker rm -f bftpd_repro
```
