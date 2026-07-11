# opencode-ssh

通过 SSH 隧道一键将远程服务器的 OpenCode 服务代理到本地，解决使用云端opencode密钥可能泄漏的问题。密钥使用本地密钥，opencode运行在云端。

## 功能

- 自动获取 `OPENCODE_API_KEY` 和 `OPENCODE_SERVER_PASSWORD`
- 在远程服务器启动 `opencode serve`
- 建立 SSH 本地端口转发隧道
- 自动连接本地 `opencode attach` 或打开浏览器
- **退出时自动清理远程进程和 SSH 隧道**（Ctrl+C 即可）

## 安装

```bash
cp opencode-ssh.sh /usr/local/bin/opencode-ssh
sudo chmod 755 /usr/local/bin/opencode-ssh
which opencode-ssh
```

## 前置要求

- 本地已配置 SSH `~/.ssh/config`（支持 host 别名）
- 远程服务器已安装 `opencode` CLI
- 本地安装 `opencode` CLI（用于 `attach` 模式）

## 用法

```bash
opencode-ssh <ssh-host-alias> [options]
```

### 选项

| 选项                     | 说明                                | 默认值                   |
| ------------------------ | ----------------------------------- | ------------------------ |
| `-p, --remote-port PORT` | 远程 opencode serve 端口            | `0`（随机）              |
| `-l, --local-port PORT`  | 指定本地端口                        | 随机（20000-30000）      |
| `-k, --api-key KEY`      | 直接传入 `OPENCODE_API_KEY`，设置opencode密钥        | 从环境变量读取 |
| `-s, --password PASS`    | 直接传入 `OPENCODE_SERVER_PASSWORD`，用于设置opencode serve的密码 | 从环境变量读取 |
| `-b, --browser`          | 仅打开浏览器，不执行 `attach`       | `false`                  |
| `-h, --help`             | 显示帮助                            | -                        |

### 示例

```bash
# 基础用法（自动获取密钥，随机端口）
opencode-ssh myserver

# 指定远程端口
opencode-ssh myserver -p 3000

# 直接传入密钥和密码
opencode-ssh myserver -k sk-xxx -s mypassword

# 仅打开浏览器
opencode-ssh myserver -b
```

## 密钥配置

脚本按以下优先级读取 `OPENCODE_API_KEY` 和 `OPENCODE_SERVER_PASSWORD`：

1. 命令行参数（`-k` / `-s`）
2. 本地环境变量
3. 交互式输入（隐藏回显）

## 工作流程

```
本地机器                          远程服务器
├─ 读取 API Key / Password        ├─ 接收启动脚本（base64 编码）
├─ 验证 SSH 连接                 ├─ 启动 opencode serve
├─ 获取远程可用端口               ├─ 返回进程 PID
├─ 发送启动脚本并启动服务          │
├─ 建立 SSH 隧道                  │
│   localhost:LOCAL_PORT          │
│   ──────────────────→           │
│   localhost:REMOTE_PORT         │
├─ 执行 opencode attach           │
│   或打开浏览器                   │
│                                 │
└─ Ctrl+C 触发 cleanup           └─ 清理 opencode serve 进程
    ├─ kill 远程 PID（已知）          └─ 删除临时文件
    ├─ 按端口查找并 kill（fallback）
    ├─ 关闭 SSH 控制 socket
    └─ 扫描并清理残留 SSH 进程
```

## 清理机制

退出时（`Ctrl+C` 或脚本正常结束）自动执行：

1. **远程进程清理**
   - 先尝试用已知的 PID kill
   - fallback 通过端口查找进程（支持 `lsof` / `ss` / `fuser` / `/proc/net/tcp`）
   - 删除远程临时文件（`.pid` / `.session` / `.log`）

2. **SSH 隧道清理**
   - 优雅关闭 SSH 控制 socket（`ssh -O exit`）
   - 失败时强制 kill 对应 SSH 进程
   - 兜底扫描本地端口，清理残留 SSH 转发

## 安全说明

- API Key 和 Password 通过 **base64 编码**后传输，避免命令行参数暴露
- 远程脚本执行后立即清理环境变量
- 不使用 `StrictHostKeyChecking=no`
- 临时文件使用 `mktemp` 规范创建

## 常见问题

### Q: 远程进程没有清理？

确保使用的是最新版本脚本。旧版本存在 `REMOTE_PID` 未解析的问题，会导致远程进程残留。修复后的版本通过 base64 编码传递远程清理脚本，避免引号嵌套导致的变量展开问题。

### Q: SSH 隧道残留？

检查是否有旧的 `ssh -f -N -M` 进程：

```bash
pgrep -a -f 'ssh.*-f.*-N.*-M'
```

手动清理：

```bash
kill -9 <PID>
rm -f /tmp/opencode-ssh-*.sock
```

### Q: 远程服务器没有 `ss` / `lsof` / `fuser`？

脚本会自动检测可用工具，只要有一个存在即可。如果都没有，会尝试通过 `/proc/net/tcp` 手动解析 inode 查找进程。

## License

MIT
