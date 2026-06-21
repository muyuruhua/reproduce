# 漏洞复现完整流程 (CVE 注册用)

> **目标**: 审核人员能够在自己的环境中独立复现 vulnerability/ 目录中的所有 6,613 个漏洞。

---

## 架构说明

本项目依赖三层资源：

```
Layer 1: Docker 镜像 (≈17 GB)       ← 目标程序的编译环境 + ASAN + AFL 重放工具
Layer 2: Results Tarballs (种子)     ← 模糊测试产生的 crash/violation 种子文件
Layer 3: 复现脚本                    ← replay_crash.sh / replay_logical_vuln.sh
```

```
┌─────────────────────────────────────────────────────────────┐
│                    reproduce/ 目录                          │
│                                                             │
│  scripts/                                                   │
│  ├── build_all_images.sh    ← 从源码构建 (无需下载镜像)      │
│  ├── export_images.sh       ← 从本地 Docker daemon 导出镜像  │
│  ├── load_images.sh         ← 导入镜像到 Docker daemon       │
│  ├── extract_seeds.sh       ← 从 results tarball 提取种子    │
│  ├── replay_crash.sh        ← 通用崩溃重放+验证脚本          │
│  └── replay_logical_vuln.sh ← 通用逻辑漏洞重放+Oracle验证    │
│                                                             │
│  <target>/README.md         ← 每个目标的详细复现指南         │
│  <target>/reproduce.sh      ← 一键复现脚本                   │
│                                                             │
│  HOW_TO_REPRODUCE.md        ← 本文件                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 步骤 0: 前置条件

```bash
# 0a. 确认 Docker 可用
docker run --rm hello-world

# 0b. 确认本机架构支持
uname -m  # 应为 x86_64
```

---

## 步骤 1: 获取 Docker 镜像 (选一)

### 方案 A: 从源码构建 (无需依赖外部文件) ✅ 推荐给审核人员

```bash
# 先获取 ChatAFL-master 源码
git clone <repo_url> ChatAFL-master
cd ChatAFL-master

# 一键构建全部 10 个镜像 (约 1-3 小时，取决于 CPU)
export PROJECT_ROOT=$(pwd)
bash reproduce/scripts/build_all_images.sh
```

### 方案 B: 从导出文件导入 (如果提供了镜像 tarball)

```bash
# 从 GitHub Releases / Git LFS 下载镜像文件后
bash reproduce/scripts/load_images.sh ./docker_images/
```

### 方案 C: 从 Docker Registry 拉取

```bash
# 如果镜像已推送到 GHCR / Docker Hub
docker pull ghcr.io/<org>/lightftp:latest
docker pull ghcr.io/<org>/bftpd:latest
# ... etc
```

---

## 步骤 2: 验证镜像完整性

```bash
# 确认所有 10 个镜像存在
for img in lightftp bftpd proftpd pure-ftpd exim live555 kamailio forked-daapd lighttpd1 mosquitto-v2.0.18; do
    docker image inspect "$img:latest" >/dev/null 2>&1 && echo "✓ $img" || echo "✗ $img MISSING"
done
```

---

## 步骤 3: 理解 vulnerability/ 目录中的 Excel 报告

```bash
ls -lh vulnerability/
# bftpd_漏洞发现_20260606145639.xlsx        ← BFTPD 6.1: 1,118 漏洞
# exim_漏洞发现_20260607064950.xlsx         ← Exim 4.96: 1,050 漏洞
# forked-daapd_漏洞发现_20260607124945.xlsx  ← forked-daapd 27.2: 199 漏洞
# kamailio_漏洞发现_20260607170503.xlsx     ← Kamailio 5.8.0: 343 漏洞
# lightftp_漏洞发现_20260607222551.xlsx     ← LightFTP v2.3: 291 漏洞
# lighttpd1_漏洞发现_20260607230915.xlsx    ← lighttpd 1.4.72: 125 漏洞
# live555_漏洞发现_20260608001352.xlsx      ← LIVE555 RTSP: 370 漏洞
# mosquitto-v2.0.18_漏洞发现_20260621153215.xlsx ← Mosquitto 2.0.18: 749 漏洞
# proftpd_漏洞发现_20260608011731.xlsx     ← ProFTPD 1.3.9rc1: 1,204 漏洞
# pure-ftpd_漏洞发现_20260615031029.xlsx   ← Pure-FTPd 1.0.51: 1,164 漏洞
```

每个 xlsx 包含 4-5 个 sheet：
- **Vulnerability List**: 每条漏洞的 severity, category, CWE, CVE reference, description
- **Summary**: 漏洞类型统计、CWE 分布、CVE 对照
- **CVE History**: 与已知 CVE 的关联分析
- **Reproduction Script Evaluation**: 复现脚本的可用性评估
- 部分包含 **Reproduction Seeds / Payload Examples**

---

## 步骤 4: 复现流程 (端到端)

### 4A. 崩溃复现 (Memory Corruption)

仅 4 个目标有可复现的崩溃：**bftpd, kamailio, proftpd, live555**。

```bash
# === BFTPD Heap Overflow (CWE-122) ===
# 步骤 1: 从 results tarball 提取 crash 种子
bash reproduce/scripts/extract_seeds.sh \
    key_experiment/ten_groups_data_ten/results-bftpd_Mar-16_23-10-02_ten \
    bftpd ./seeds/bftpd

# 步骤 2: 重放 crash 种子
bash reproduce/scripts/replay_crash.sh bftpd \
    ./seeds/bftpd/crashes/<任意种子文件> \
    /tmp/bftpd_crash_out

# 步骤 3: 查看结果
grep "CRASH DETECTED" /tmp/bftpd_crash_out/replay.log
# 预期: [CRASH DETECTED] replay #N: server crashed! exit_code=134


# === ProFTPD Heap UAF (CWE-416) ===
bash reproduce/scripts/extract_seeds.sh \
    key_experiment/ten_groups_data_ten/results-proftpd_Mar-16_23-10-02_ten \
    proftpd ./seeds/proftpd

bash reproduce/scripts/replay_crash.sh proftpd \
    ./seeds/proftpd/crashes/<任意种子文件> \
    /tmp/proftpd_crash_out


# === Kamailio Heap Corruption (CWE-122) ===
bash reproduce/scripts/extract_seeds.sh \
    key_experiment/ten_groups_data_ten/results-kamailio_Mar-16_23-10-02_ten \
    kamailio ./seeds/kamailio

bash reproduce/scripts/replay_crash.sh kamailio \
    ./seeds/kamailio/crashes/<任意种子文件> \
    /tmp/kamailio_crash_out
```

### 4B. 逻辑漏洞复现 (Protocol Logic Violations)

**全部 10 个目标** 都有可复现的逻辑漏洞。

```bash
# === 以 BFTPD 为例 (CRLF 注入 + FTP Bounce + 状态违规 + ...) ===
bash reproduce/scripts/replay_logical_vuln.sh bftpd \
    ./seeds/bftpd/violations/ \
    /tmp/bftpd_logical_out

# 查看确认的漏洞
grep "CONFIRMED" /tmp/bftpd_logical_out/*/verdict.txt

# === Exim SMTP 走私 ===
bash reproduce/scripts/replay_logical_vuln.sh exim \
    ./seeds/exim/violations/ \
    /tmp/exim_logical_out

# === Mosquitto ACL bypass + 会话劫持 ===
bash reproduce/scripts/replay_logical_vuln.sh mosquitto-v2.0.18 \
    ./seeds/mosquitto-v2.0.18/violations/ \
    /tmp/mosquitto_logical_out
```

---

## 步骤 5: 验证判据

### 崩溃验证判据
| 信号 | 含义 | CWE |
|------|------|-----|
| `SIGABRT` (6) | ASAN 检测到内存错误后主动 abort | CWE-122/416/415 |
| `SIGSEGV` (11) | 段错误（未启用 ASAN 时） | CWE-119/125 |

确认复现成功：
- 输出中有 `[CRASH DETECTED]` 行
- 输出中有 `AddressSanitizer: heap-buffer-overflow` 或 `heap-use-after-free`
- 调用栈指向目标程序的特定函数

### 逻辑漏洞验证判据

Oracle 验证引擎检查以下安全属性：

| 属性 | CWE | 判据 | 示例 |
|------|-----|------|------|
| AUTH_BYPASS | CWE-306 | 未认证数据命令返回 2xx | `PASS` without `USER` returns 230 |
| STATE_VIOLATION | CWE-696 | RFC 违规序列被接受 | `RNTO` without `RNFR` returns 250 |
| CRLF_INJECTION | CWE-93 | 命令参数含内嵌 CRLF | `USER admin\r\nPASS x` 被解释为两条命令 |
| FTP_BOUNCE | CWE-441 | PORT 指向内部 IP 被接受 | `PORT 127,0,0,1,...` returns 200 |
| PATH_TRAVERSAL | CWE-22 | `../` 路径被接受 | `RETR ../../../etc/passwd` returns 150 |
| SMUGGLING | CWE-444 | 多 CL 头 / CL+TE 共存 | 2个 `Content-Length` 头被处理 |
| INFO_LEAK | CWE-200 | 敏感信息出现在响应中 | 响应含 `root:x:0:0:` |
| ACL_BYPASS | CWE-284 | 非特权客户端访问 $SYS | SUBSCRIBE `$SYS/broker/version` 返回 0x00 |
| PRIVILEGE_ESC | CWE-250 | Will 消息写入 $SYS | CONNECT Will Topic=`$SYS/broker/...` 被接受 |
| SESSION_HIJACK | CWE-384 | 空 ClientID + clean_session=0 | CONNACK 返回 0x00 (成功) |

---

## 每个目标的一键复现命令

| 目标 | 镜像 | 端口 | 复现命令 |
|------|------|------|---------|
| **bftpd** | `bftpd:latest` | TCP 21 | `bash reproduce/bftpd/reproduce.sh <results_dir>` |
| **exim** | `exim:latest` | TCP 25 | `bash reproduce/exim/reproduce.sh <results_dir>` |
| **forked-daapd** | `forked-daapd:latest` | TCP 3689 | `bash reproduce/forked-daapd/reproduce.sh <results_dir>` |
| **kamailio** | `kamailio:latest` | UDP 5060 | `bash reproduce/kamailio/reproduce.sh <results_dir>` |
| **lightftp** | `lightftp:latest` | TCP 2200 | `bash reproduce/lightftp/reproduce.sh <results_dir>` |
| **lighttpd1** | `lighttpd1:latest` | TCP 8080 | `bash reproduce/lighttpd1/reproduce.sh <results_dir>` |
| **live555** | `live555:latest` | TCP 8554 | `bash reproduce/live555/reproduce.sh <results_dir>` |
| **mosquitto-v2.0.18** | `mosquitto-v2.0.18:latest` | TCP 1883 | `bash reproduce/mosquitto-v2.0.18/reproduce.sh <results_dir>` |
| **proftpd** | `proftpd:latest` | TCP 21 | `bash reproduce/proftpd/reproduce.sh <results_dir>` |
| **pure-ftpd** | `pure-ftpd:latest` | TCP 21 | `bash reproduce/pure-ftpd/reproduce.sh <results_dir>` |

---

## 常见问题

### Docker 镜像太大无法上传 GitHub?
**解决方案**:
1. **Git LFS** (每个文件 >100MB): `git lfs track 'docker_images/*.tar.gz'`
2. **GitHub Releases**: 将镜像作为 release assets 附加（可上传 ≤2GB 文件）
3. **Docker Registry**: 推送到 GHCR (ghcr.io) — GitHub Packages 免费提供
4. **仅提供 Dockerfile**: 让审核人员自己构建（方案 A）

### 本地已有镜像，如何复用?
```bash
# 导出当前系统中的镜像
bash reproduce/scripts/export_images.sh ./docker_images/

# 然后上传 docker_images/ 目录
```

### 审核人员没有 NVIDIA GPU 会影响吗?
不会。所有目标都是 CPU-only 的网络服务程序（FTP/SMTP/HTTP/MQTT/SIP/RTSP 服务器），不依赖 GPU。

### 复现失败怎么办?
1. 检查 Docker 日志: `docker logs <container_id>`
2. 确认使用 `--network host --cap-add SYS_PTRACE` (ASAN 需要)
3. 对于 forked-daapd 和 live555 的崩溃: 需在 AFL persistent mode 环境中复现
4. 对于 ProFTPD: 不要用 `nc -z` 检查端口，查看 README 中的替代方案

---

## 报告格式建议 (给 CVE 审核)

```
复现环境:
  - Ubuntu 22.04 x86_64
  - Docker 24.0.x
  - 镜像: bftpd:latest (基于 ubuntu:18.04)

复现步骤:
  1. docker run --rm --network host --cap-add SYS_PTRACE \
       -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
       -v /path/to/crash_seed:/tmp/seed:ro \
       bftpd:latest /bin/bash -c "..."

确认结果:
  - 服务器在第 3 次重放时崩溃 (exit_code=134, SIGABRT)
  - ASAN 报告: heap-buffer-overflow in process_command()
  - 漏洞确认: CWE-122, CVSS 9.8 (可远程触发，无需认证)
```
