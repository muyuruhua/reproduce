# ChatAFL-Master 漏洞复现包

> **用途**: CVE 注册时提交给审核人员，提供完整的 Docker 镜像 + 种子 + 一键复现脚本。
> **覆盖**: 10 个目标程序, 7 种网络协议, 共 6,613 个漏洞 (741 内存崩溃 + 5,696 逻辑漏洞)。

---

## 审核人员快速开始

```bash
# 1. 导入镜像（首次，约3分钟）
for f in docker_images/*.tar.gz; do docker load -i "$f"; done

# 2. 一键复现全部（约8分钟）
bash quickstart.sh --demo

# 3. 从 Excel 精确复现某条漏洞
bash scripts/reproduce_from_excel.sh bftpd viol 0x0020
```

> 详细操作说明：[审核人员操作指南.md](审核人员操作指南.md) ｜ [漏洞复现演示.md](漏洞复现演示.md)

---

## 目录结构

```
reproduce/
├── 审核人员操作指南.md          # ★ 审核员第一入口 — 3步操作
├── 漏洞复现演示.md              # ★ Excel→种子→复现 逐步骤演示
├── quickstart.sh                # 一键验证全部10个目标
├── docker_images/               # 11个Docker镜像（6.4GB, Git LFS）
├── vulnerability/               # 10个Excel漏洞报告（2.6MB）
├── ten_groups_data_ten/         # 原始模糊测试数据（290个tar.gz, 1.4GB）
├── scripts/
│   ├── reproduce_from_excel.sh  # ★ 核心: 从Excel Category到复现一条命令
│   ├── replay_crash.sh          # 崩溃重放
│   ├── replay_logical_vuln.sh   # 逻辑漏洞重放+Oracle验证
│   ├── build_all_images.sh      # 从源码构建全部镜像
│   ├── export_images.sh         # 导出镜像为tar.gz
│   ├── load_images.sh           # 导入tar.gz到Docker
│   └── extract_seeds.sh         # 从tarball批量提取种子
├── bftpd/    ├── exim/       ├── forked-daapd/  ├── kamailio/
├── lightftp/ ├── lighttpd1/  ├── live555/
├── mosquitto-v2.0.18/         ├── proftpd/      └── pure-ftpd/
│   (每个含 README.md + reproduce.sh + seeds/样本种子)
└── README.md                   # 本文件
```

---

## 核心脚本速查

| 脚本 | 用途 | 示例 |
|------|------|------|
| `quickstart.sh --demo` | 一键复现全部10个目标（每目标1个种子） | `bash quickstart.sh --demo` |
| `reproduce_from_excel.sh` | **Excel Category → 复现** | `bash scripts/reproduce_from_excel.sh bftpd viol 0x0020` |
| `replay_crash.sh` | 手动重放单个崩溃种子 | `bash scripts/replay_crash.sh bftpd <种子文件>` |
| `replay_logical_vuln.sh` | 手动重放单个逻辑漏洞种子 | `bash scripts/replay_logical_vuln.sh bftpd <种子文件>` |

---

## 漏洞概览

| # | 目标 | 协议 | 崩溃 | 逻辑漏洞 | Docker复现(persistent) |
|---|------|------|:---:|:---:|:---:|
| 1 | **bftpd** 6.1 | FTP | 500 | 618 | ✅ 崩溃+逻辑 |
| 2 | **exim** 4.96 | SMTP | 0 | 885 | ✅ 逻辑漏洞 |
| 3 | **forked-daapd** 27.2 | DAAP/HTTP | 39 | 160 | ✅ 逻辑 / ⚠️崩溃需AFL |
| 4 | **kamailio** 5.8.0 | SIP | 68 | 275 | ✅ 逻辑 / ⚠️崩溃需AFL |
| 5 | **lightftp** v2.3 | FTP | 0 | 291 | ✅ 全部 |
| 6 | **lighttpd1** 1.4.72 | HTTP | 0 | 124 | ✅ 全部 |
| 7 | **live555** RTSP | RTSP | 72 | 298 | ✅ 全部(persistent) |
| 8 | **mosquitto-v2.0.18** | MQTT | 0 | 749 | ✅ 全部 |
| 9 | **proftpd** 1.3.9rc1 | FTP | 62 | 1,142 | ✅ 全部(persistent) |
| 10 | **pure-ftpd** 1.0.51 | FTP | 0 | 1,164 | ✅ 全部 |

> ⚠️(AFL) = 崩溃依赖 AFL persistent-mode fork-server 数千次迭代累积的内部状态，Docker 无法复现。种子在 AFLNet 中已验证为 replayable-crashes，可作 CVE 证据。

---

## 漏洞类型

### 内存破坏 (741个, 5个目标)
- Heap buffer overflow (CWE-122): bftpd ✅, kamailio ⚠️(AFL)
- Use-After-Free (CWE-416): proftpd ✅, live555 ✅, forked-daapd ⚠️(AFL)
- Stack buffer overflow (CWE-121): forked-daapd ⚠️(AFL)
> ✅ = Docker persistent-mode可触发  ⚠️ = 需AFL persistent-mode (种子已存在于replayable-crashes/)

### 逻辑漏洞 (5,696个, 10个目标)

| 类型 | CWE | 影响目标 |
|------|-----|---------|
| CRLF注入/命令走私 | CWE-93 | FTP系列, exim, lighttpd1 |
| FTP Bounce | CWE-441 | FTP系列 |
| 状态机违规 | CWE-696 | 全部 |
| 认证/授权绕过 | CWE-306/862 | 全部 |
| 路径遍历 | CWE-22 | FTP系列, lighttpd1 |
| HTTP请求走私 | CWE-444 | lighttpd1, forked-daapd |
| ACL绕过 ($SYS) | CWE-284 | mosquitto-v2.0.18 |
| 会话劫持 | CWE-384 | mosquitto-v2.0.18 |
| 权限提升 (Will $SYS) | CWE-250 | mosquitto-v2.0.18 ★新发现 |
| DoS/资源耗尽 | CWE-400/770 | 多个目标 |

---

## 前置条件

- **OS**: Ubuntu 20.04+ / Debian 11+ (x86_64)
- **Docker**: 20.10+
- **磁盘**: ≥ 25 GB（镜像6.4G压缩 → 解压后约17G）
- **内存**: ≥ 8 GB

---

## 镜像管理

镜像已通过 Git LFS 随仓库分发（`docker_images/*.tar.gz`）。如需从源码重建：

```bash
export PROJECT_ROOT=/path/to/ChatAFL-master
bash scripts/build_all_images.sh
```

---

## 数据来源关系

```
ten_groups_data_ten/results-*/out-*.tar.gz    ← 290个原始tarball (Fuzzer 24h运行)
        │
        ├── Python分析脚本 → vulnerability/*.xlsx  ← 10个Excel漏洞报告
        │
        └── 种子提取 → <target>/seeds/            ← 样本种子 (3 crash + 3 viol)
                        │
                        └── reproduce_from_excel.sh ← 审核员一条命令复现
```
