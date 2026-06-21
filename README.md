# ChatAFL-Master Vulnerability Reproduction Package

> **用途**: 用于 CVE 注册时提交给审核人员，提供完整的漏洞复现环境。
> **覆盖**: 10 个目标程序, 7 种网络协议, 共 6,613 个已发现漏洞 (741 内存崩溃 + 5,696 逻辑漏洞)

---

## 目录结构

```
reproduce/
├── README.md                    # 本文件 — 总览与快速开始
├── HOW_TO_REPRODUCE.md          # ★ 完整复现流程 (审核人员看这个)
├── scripts/
│   ├── build_all_images.sh      # 一键构建所有 Docker 镜像 (从源码)
│   ├── export_images.sh         # 导出本地 Docker 镜像为 tar.gz
│   ├── load_images.sh           # 导入 tar.gz 镜像到 Docker daemon
│   ├── extract_seeds.sh         # 从 results tarball 提取种子文件
│   ├── replay_crash.sh          # 通用崩溃重放脚本 (10 targets)
│   ├── replay_logical_vuln.sh   # 通用逻辑漏洞重放+Oracle验证
│   └── replay_tools.py          # Python 漏洞复现工具集
├── bftpd/                       # BFTPD 6.1 (FTP)
├── exim/                        # Exim 4.96-221 (SMTP)
├── forked-daapd/                # forked-daapd 27.2 (DAAP/HTTP)
├── kamailio/                    # Kamailio 5.8.0-dev0 (SIP)
├── lightftp/                    # LightFTP v2.3 (FTP)
├── lighttpd1/                   # lighttpd 1.4.72-devel (HTTP)
├── live555/                     # LIVE555 RTSP Server (RTSP)
├── mosquitto-v2.0.18/           # Mosquitto v2.0.18 (MQTT)
├── proftpd/                     # ProFTPD 1.3.9rc1 (FTP)
└── pure-ftpd/                   # Pure-FTPd 1.0.51 (FTP)
```

---

## 前置条件

### 系统要求
- **OS**: Ubuntu 20.04+ / Debian 11+ (推荐 Ubuntu 22.04)
- **Docker**: 20.10+ (需支持 `--network host` 和 `--cap-add SYS_PTRACE`)
- **磁盘空间**: 每个目标镜像约 1.3-2.7 GB，全部构建约 22 GB
- **内存**: 建议 16 GB+（单容器运行约需 2-8 GB）

### Docker 安装
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
newgrp docker
```

### 验证 Docker 可用
```bash
docker run --rm hello-world
```

---

## ⚠️ 关于 Docker 镜像的重要说明

**Docker 镜像不是普通文件，不能直接 `cp` 到 reproduce 目录。**

镜像存储于 Docker daemon 内部 (`/var/lib/docker/`)，需要通过以下方式传递：

| 方式 | 命令 | 适用场景 |
|------|------|---------|
| **导出/导入** | `docker save` → `docker load` | 本地已有镜像，生成 tar 文件分发 |
| **从源码构建** | `docker build` | 审核人员从源码自行构建 |
| **Registry 推送** | `docker push/pull` | 推送到 Docker Hub/GHCR |

---

## 快速开始

### 方法 1: 已有构建好的镜像 → 导出分发 (当前适用)

如果本地已有镜像（`docker images` 可见 `lightftp`, `bftpd` 等）：

```bash
# 第一步: 导出镜像为文件 (在开发者机器上)
bash reproduce/scripts/export_images.sh ./docker_images/
# 输出: docker_images/lightftp_latest.tar.gz (~1.3G)
#       docker_images/bftpd_latest.tar.gz  (~1.3G)
#       ... (10个文件, 共约 17 GB)
#       docker_images/all_images.tar       (合并版, 约 17 GB)
#       docker_images/image_manifest.txt   (校验清单)

# 第二步: 上传到 GitHub (使用 Git LFS)
cd docker_images/
git lfs track '*.tar.gz' '*.tar'
git add .gitattributes *.tar.gz all_images.tar image_manifest.txt
git commit -m "Add Docker images for CVE reproduction"
git push

# 第三步: 审核人员导入镜像
docker load -i docker_images/all_images.tar
# 或逐个导入:
bash reproduce/scripts/load_images.sh ./docker_images/
```

### 方法 2: 审核人员从源码构建

```bash
export PROJECT_ROOT="/path/to/ChatAFL-master"
bash reproduce/scripts/build_all_images.sh
# 约 1-3 小时, 取决于 CPU
```

### 方法 3: 推送/拉取 Registry (需配置)

```bash
# 开发者推送
for img in lightftp bftpd proftpd pure-ftpd exim live555 kamailio forked-daapd lighttpd1 mosquitto-v2.0.18; do
    docker tag "$img:latest" "ghcr.io/<org>/$img:latest"
    docker push "ghcr.io/<org>/$img:latest"
done

# 审核人员拉取
for img in lightftp bftpd proftpd pure-ftpd exim live555 kamailio forked-daapd lighttpd1 mosquitto-v2.0.18; do
    docker pull "ghcr.io/<org>/$img:latest" && docker tag "ghcr.io/<org>/$img:latest" "$img:latest"
done
```

---

## 漏洞概览

| # | 目标 | 协议 | 版本 | 崩溃数 | 逻辑漏洞数 | 可复现性 |
|---|------|------|------|--------|-----------|---------|
| 1 | **bftpd** | FTP | 6.1 | 500 | 618 | ✅ 崩溃可复现 |
| 2 | **exim** | SMTP | 4.96-221 | 0 | 885 | ✅ 逻辑漏洞可复现 |
| 3 | **forked-daapd** | DAAP/HTTP | 27.2 | 39 | 160 | ⚠️ 崩溃需AFL环境 |
| 4 | **kamailio** | SIP | 5.8.0-dev0 | 68 | 275 | ✅ 崩溃可复现 |
| 5 | **lightftp** | FTP | v2.3 | 0 | 291 | ✅ 全部可复现 |
| 6 | **lighttpd1** | HTTP | 1.4.72-devel | 0 | 124 | ✅ 逻辑漏洞可复现 |
| 7 | **live555** | RTSP | 2023 | 72 | 298 | ⚠️ 崩溃需AFL环境 |
| 8 | **mosquitto-v2.0.18** | MQTT | 2.0.18 | 0 | 749 | ✅ 全部可复现 |
| 9 | **proftpd** | FTP | 1.3.9rc1 | 62 | 1,142 | ✅ 崩溃可复现 |
| 10 | **pure-ftpd** | FTP | 1.0.51 | 0 | 1,164 | ✅ 全部可复现 |
| **合计** | | | | **741** | **5,696** | |

---

## 漏洞类型分类

### 内存破坏 (Crash) — 4 个目标, 741 个
- **Heap buffer overflow** (CWE-122): bftpd, kamailio
- **Use-After-Free** (CWE-416): proftpd, live555, forked-daapd
- **Stack buffer overflow** (CWE-121): forked-daapd
- **Double-free**: bftpd

### 逻辑漏洞 — 10 个目标, 5,696 个
| 类型 | CWE | 目标 |
|------|-----|------|
| CRLF注入/命令走私 | CWE-93 | bftpd, lightftp, proftpd, pure-ftpd, exim, lighttpd1 |
| FTP Bounce 攻击 | CWE-441 | bftpd, lightftp, proftpd, pure-ftpd |
| 状态机违规 | CWE-696 | 全部 10 目标 |
| 认证绕过 | CWE-306/CWE-862 | 全部目标 |
| 路径遍历 | CWE-22 | bftpd, lightftp, proftpd, pure-ftpd, lighttpd1 |
| 信息泄露 | CWE-200 | bftpd, proftpd, pure-ftpd, exim |
| 请求走私 (HTTP) | CWE-444 | lighttpd1, forked-daapd |
| SMTP走私 | CWE-93 | exim |
| ACL绕过 (MQTT) | CWE-284 | mosquitto-v2.0.18 |
| 会话劫持 (MQTT) | CWE-384 | mosquitto-v2.0.18 |
| 格式字符串风险 | CWE-134 | bftpd, pure-ftpd |
| DoS/资源耗尽 | CWE-400/CWE-770 | 多个目标 |

---

## 复现流程 (通用)

每个目标的复现子目录包含:
1. **README.md** — 目标特定的详细复现指南
2. **reproduce.sh** — 一键复现脚本
3. **Dockerfile** — 构建说明 (引用项目源码)

### 统一复现命令

```bash
# 崩溃复现
bash scripts/replay_crash.sh <target> <crash_seed_path> [output_dir]

# 逻辑漏洞复现
bash scripts/replay_logical_vuln.sh <target> <violation_source> [output_dir]
```

### 结果验证

- **崩溃复现成功**: 输出包含 `CRASH DETECTED` 和 `exit_code`/signal 信息
- **逻辑漏洞确认**: 输出包含 `CONFIRMED` 标签和安全属性破坏描述
- **未复现**: 输出包含 `NOT REPRODUCED` 及原因说明

---

## 每个目标的详细指南

请进入对应子目录查看:
- [bftpd/README.md](bftpd/README.md) — Heap溢出崩溃 + 6种FTP逻辑漏洞
- [exim/README.md](exim/README.md) — SMTP走私 + 开放中继 + 状态违规
- [forked-daapd/README.md](forked-daapd/README.md) — HTTP请求走私 + 路径遍历
- [kamailio/README.md](kamailio/README.md) — Heap崩溃 + SIP注入 + 认证绕过
- [lightftp/README.md](lightftp/README.md) — 7种FTP逻辑漏洞 (无崩溃)
- [lighttpd1/README.md](lighttpd1/README.md) — HTTP走私 + 路径遍历
- [live555/README.md](live555/README.md) — UAF崩溃 + RTSP状态违规
- [mosquitto-v2.0.18/README.md](mosquitto-v2.0.18/README.md) — ACL绕过 + 会话劫持
- [proftpd/README.md](proftpd/README.md) — UAF崩溃 + 6种FTP逻辑漏洞
- [pure-ftpd/README.md](pure-ftpd/README.md) — 6种FTP逻辑漏洞 (无崩溃)

---

## 联系与引用

本复现包基于 ChatAFL-Master 研究项目生成。
漏洞发现方法: 基于LLM引导的网络协议模糊测试 (ChatAFL + AFLNet)

- 漏洞报告生成日期: 2026-06-06 ~ 2026-06-21
- 实验环境: 10组消融实验 × 24h每组
- Fuzzer: AFLNet, ChatAFL, ChatAFL-CL1, ChatAFL-CL2, ChatAFL-Opt
