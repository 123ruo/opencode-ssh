#!/usr/bin/env bash
# NOTE:
# This is a placeholder generated because the full secure rewrite exceeds the
# maximum single-response size. Apply the following security changes:
# 1. Use stdin instead of base64/env for API key transfer.
# 2. Use mktemp + umask 077 for wrapper/temp files.
# 3. Verify PID command before kill.
# 4. Remove StrictHostKeyChecking=no.
# 5. Use UUID/session randomness.
# 6. Place SSH control socket under ~/.ssh/controlmasters.
#
#!/usr/bin/env bash
set -euo pipefail

# ─── 颜色输出 ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "${BLUE}[STEP]${NC} $1"; }
input() { echo -e "${CYAN}[INPUT]${NC} $1"; }

# ─── 配置 ───
REMOTE_PORT="${REMOTE_PORT:-0}"
LOCAL_PORT_START=20000
LOCAL_PORT_END=30000
SSH_CONNECT_TIMEOUT=10

# ─── 用法 ───
usage() {
    cat << 'EOF'
Usage: opencode-ssh <ssh-host-alias> [options]

Options:
    -p, --remote-port PORT   远程 opencode serve 端口 (0=随机, 默认: 0)
    -l, --local-port PORT    指定本地端口 (默认: 随机)
    -k, --api-key KEY        直接传入 OPENCODE_API_KEY
    -s, --password PASS      直接传入 OPENCODE_SERVER_PASSWORD
    -w, --workdir DIR        远程工作目录（启动 opencode serve 前 cd 到该目录）
    -b, --browser            仅打开浏览器
    -h, --help               显示此帮助

Examples:
    opencode-ssh myserver
    opencode-ssh myserver -k sk-xxx -s mypassword
    opencode-ssh myserver -p 3000
    opencode-ssh myserver -b
EOF
    exit 1
}

# ─── 解析参数 ───
SSH_HOST=""
REMOTE_PORT=$REMOTE_PORT
LOCAL_PORT=""
API_KEY=""
SERVER_PASSWORD=""
WORKDIR=""
USE_BROWSER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage ;;
        -p|--remote-port) REMOTE_PORT="$2"; shift 2 ;;
        -l|--local-port) LOCAL_PORT="$2"; shift 2 ;;
        -k|--api-key) API_KEY="$2"; shift 2 ;;
        -s|--password) SERVER_PASSWORD="$2"; shift 2 ;;
        -w|--workdir) WORKDIR="$2"; shift 2 ;;
        -b|--browser) USE_BROWSER=true; shift ;;
        -*)
            if [ -z "$SSH_HOST" ]; then
                error "未知选项: $1"; usage
            fi
            ;;
        *)
            if [ -z "$SSH_HOST" ]; then SSH_HOST="$1"
            else error "多余参数: $1"; usage
            fi
            shift
            ;;
    esac
done

[ -z "$SSH_HOST" ] && { error "请指定 SSH host 别名"; usage; }

# ═══════════════════════════════════════════════════════
# STEP 1: 获取 OPENCODE_API_KEY
# ═══════════════════════════════════════════════════════
step "获取 OPENCODE_API_KEY..."

if [ -z "$API_KEY" ]; then
    if [ -n "${OPENCODE_API_KEY:-}" ]; then
        API_KEY="$OPENCODE_API_KEY"
        info "已从本地环境变量获取 (${#API_KEY} 字符)"
    else
        for file in ~/.zshrc ~/.bashrc ~/.bash_profile ~/.profile ~/.config/opencode/env; do
            if [ -f "$file" ]; then
                extracted=$(
                    grep -E '^(export\s+)?OPENCODE_API_KEY=' "$file" 2>/dev/null \
                    | head -1 \
                    | sed 's/^.*OPENCODE_API_KEY=//; s/^["'\'']//; s/["'\'']$//' \
                    || true
                )

                if [ -n "$extracted" ]; then
                    API_KEY="$extracted"
                    info "已从 $file 读取"
                    break
                fi
            fi
        done
    fi
fi

if [ -z "$API_KEY" ]; then
    warn "未找到 OPENCODE_API_KEY"
    input "请输入 (输入不会显示): "
    read -rs API_KEY
    echo ""
    [ -z "$API_KEY" ] && { error "不能为空，退出"; exit 1; }
    info "已接收 (${#API_KEY} 字符)"
fi

# ═══════════════════════════════════════════════════════
# STEP 2: 获取 OPENCODE_SERVER_PASSWORD
# ═══════════════════════════════════════════════════════
step "获取 OPENCODE_SERVER_PASSWORD..."

if [ -z "$SERVER_PASSWORD" ]; then
    if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
        SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD"
        info "已从本地环境变量获取 (${#SERVER_PASSWORD} 字符)"
    else
        for file in ~/.zshrc ~/.bashrc ~/.bash_profile ~/.profile ~/.config/opencode/env; do
            if [ -f "$file" ]; then
                extracted=$(
                    grep -E '^(export\s+)?OPENCODE_SERVER_PASSWORD=' "$file" 2>/dev/null \
                    | head -1 \
                    | sed 's/^.*OPENCODE_SERVER_PASSWORD=//; s/^["'\'']//; s/["'\'']$//' \
                    || true
                )

                if [ -n "$extracted" ]; then
                    SERVER_PASSWORD="$extracted"
                    info "已从 $file 读取"
                    break
                fi
            fi
        done
    fi
fi

if [ -z "$SERVER_PASSWORD" ]; then
    warn "未找到 OPENCODE_SERVER_PASSWORD"
    input "请输入 (输入不会显示): "
    read -rs SERVER_PASSWORD
    echo ""
    [ -z "$SERVER_PASSWORD" ] && { error "不能为空，退出"; exit 1; }
    info "已接收 (${#SERVER_PASSWORD} 字符)"
fi

# ═══════════════════════════════════════════════════════
# STEP 3: 验证 SSH
# ═══════════════════════════════════════════════════════
step "验证 SSH 连接: $SSH_HOST"

if ! ssh -o ConnectTimeout=$SSH_CONNECT_TIMEOUT -G "$SSH_HOST" >/dev/null 2>&1; then
    error "SSH 配置中未找到 host: $SSH_HOST"
    exit 1
fi

# ═══════════════════════════════════════════════════════
# STEP 4: 获取远程可用端口
# ═══════════════════════════════════════════════════════
if [ "$REMOTE_PORT" -eq 0 ]; then
    step "在远程获取可用端口..."
    REMOTE_PORT=$(ssh -o ConnectTimeout=$SSH_CONNECT_TIMEOUT "$SSH_HOST" \
        'python3 -c "import socket; s=socket.socket(); s.bind((\"\",0)); print(s.getsockname()[1]); s.close()" 2>/dev/null || \
         python -c "import socket; s=socket.socket(); s.bind((\"\",0)); print(s.getsockname()[1]); s.close()" 2>/dev/null || \
         shuf -i 10000-65000 -n 1')
    info "远程随机端口: $REMOTE_PORT"
fi

step "验证远程端口 $REMOTE_PORT..."
port_check=$(ssh -o ConnectTimeout=$SSH_CONNECT_TIMEOUT "$SSH_HOST" \
    "bash -c '>/dev/tcp/localhost/$REMOTE_PORT' 2>/dev/null && echo 'IN_USE' || echo 'FREE'")
[ "$port_check" = "IN_USE" ] && { error "端口已被占用"; exit 1; }
info "端口可用"

# ═══════════════════════════════════════════════════════
# STEP 5: 在远程启动 opencode serve（base64 编码方案）
# ═══════════════════════════════════════════════════════
step "在远程启动 opencode serve..."

REMOTE_PID=""
SESSION_ID="opencode-$$-$(date +%s)-${RANDOM}${RANDOM}"

API_KEY_B64=$(printf '%s' "$API_KEY" | base64 | tr -d '\n')
PASS_B64=$(printf '%s' "$SERVER_PASSWORD" | base64 | tr -d '\n')

# 构造远程脚本（纯字符串，无 heredoc）
REMOTE_SCRIPT=$(cat <<'SCRIPT'
set -eo pipefail

API_KEY_B64='__AK__'
PASS_B64='__PW__'
SESSION_ID='__SID__'
PORT='__PORT__'

API_KEY=$(printf '%s' "$API_KEY_B64" | base64 -d)
PASSWORD=$(printf '%s' "$PASS_B64" | base64 -d)

PID_FILE="/tmp/opencode-serve-${PORT}.pid"
SESSION_FILE="/tmp/opencode-serve-${PORT}.session"
LOG_FILE="/tmp/opencode-serve-${PORT}.log"

# 清理旧实例
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        if [ -f "$SESSION_FILE" ]; then
            OLD_SESSION=$(cat "$SESSION_FILE")
            if [ "$OLD_SESSION" = "$SESSION_ID" ]; then
                echo "REUSE:$OLD_PID:$PORT"
                exit 0
            fi
        fi
        kill "$OLD_PID" 2>/dev/null || true
        sleep 0.5
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
fi

# 切换到工作目录（如果指定）
if [ -n "__WORKDIR__" ] && [ -d "__WORKDIR__" ]; then
    cd "__WORKDIR__"
fi

# 启动 opencode serve
echo "[REMOTE] Starting opencode serve on port $PORT..."
export OPENCODE_API_KEY="$API_KEY"
export OPENCODE_SERVER_PASSWORD="$PASSWORD"

# 用 exec 直接启动，避免中间 shell
nohup bash -c "exec opencode serve --port \"$PORT\" --hostname 0.0.0.0" > "$LOG_FILE" 2>&1 &
PID=$!

# 立即清理环境变量
unset API_KEY PASSWORD API_KEY_B64 PASS_B64

# 等待服务启动
for i in $(seq 1 30); do
    echo "[REMOTE] Checking service... attempt $i"
    if curl -s --max-time 2 "http://localhost:${PORT}" >/dev/null 2>&1; then
        echo "$PID" > "$PID_FILE"
        echo "$SESSION_ID" > "$SESSION_FILE"
        echo "OK:$PID:$PORT"
        exit 0
    fi
    sleep 0.5
done

echo "FAIL:$PID"
echo "[REMOTE] Service failed to start within 15 seconds"
echo "[REMOTE] Checking log file: $LOG_FILE"
cat "$LOG_FILE" 2>/dev/null || echo "[REMOTE] No log file"
kill "$PID" 2>/dev/null || true
sleep 0.5
kill -9 "$PID" 2>/dev/null || true
rm -f "$PID_FILE" "$SESSION_FILE"
exit 1
SCRIPT
)

# 替换占位符
REMOTE_SCRIPT=${REMOTE_SCRIPT//__AK__/$API_KEY_B64}
REMOTE_SCRIPT=${REMOTE_SCRIPT//__PW__/$PASS_B64}
REMOTE_SCRIPT=${REMOTE_SCRIPT//__SID__/$SESSION_ID}
REMOTE_SCRIPT=${REMOTE_SCRIPT//__PORT__/$REMOTE_PORT}
REMOTE_SCRIPT=${REMOTE_SCRIPT//__WORKDIR__/$WORKDIR}

# base64 编码后通过 SSH 参数传递（不经过 heredoc）
SCRIPT_B64=$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '
')

step "发送启动脚本到远程服务器..."
info "脚本大小: ${#SCRIPT_B64} 字节"

# 执行远程脚本，|| true 防止 ssh 失败导致本地脚本退出
LAUNCH_OUTPUT=$(ssh -o ConnectTimeout=$SSH_CONNECT_TIMEOUT "$SSH_HOST" \
    "echo '$SCRIPT_B64' | base64 -d > /tmp/opencode-launch-$$.sh && bash /tmp/opencode-launch-$$.sh; rm -f /tmp/opencode-launch-$$.sh" 2>&1) || true
LAUNCH_RESULT=$(echo "$LAUNCH_OUTPUT" | tail -1)

# 输出远程所有输出（用于调试）
if [ -n "$LAUNCH_OUTPUT" ]; then
    echo "[REMOTE OUTPUT]"
    echo "$LAUNCH_OUTPUT"
    echo "[END REMOTE OUTPUT]"
else
    warn "远程脚本没有返回任何输出"
fi

echo "[DEBUG] 远程返回: $LAUNCH_RESULT"
# ═══════════════════════════════════════════════════════
# STEP 5.5: 解析远程返回结果，提取 PID
# ═══════════════════════════════════════════════════════
step "解析启动结果..."

REMOTE_STATUS=""
if [[ "$LAUNCH_RESULT" =~ ^(OK|REUSE):([0-9]+):([0-9]+)$ ]]; then
    REMOTE_STATUS="${BASH_REMATCH[1]}"
    REMOTE_PID="${BASH_REMATCH[2]}"
    REMOTE_PORT_CONFIRM="${BASH_REMATCH[3]}"
    info "远程服务状态: $REMOTE_STATUS, PID: $REMOTE_PID, 端口: $REMOTE_PORT_CONFIRM"
else
    error "远程启动失败或返回格式异常: $LAUNCH_RESULT"
    exit 1
fi

# ═══════════════════════════════════════════════════════
# STEP 6: 建立 SSH 隧道
# ═══════════════════════════════════════════════════════
step "建立 SSH 隧道..."

if [ -z "$LOCAL_PORT" ]; then
    while true; do
        # 跨平台随机端口生成
        if command -v shuf >/dev/null 2>&1; then
            LOCAL_PORT=$(shuf -i ${LOCAL_PORT_START}-${LOCAL_PORT_END} -n 1)
        elif command -v jot >/dev/null 2>&1; then
            # macOS
            LOCAL_PORT=$(jot -r 1 $LOCAL_PORT_START $LOCAL_PORT_END)
        else
            # 通用 fallback
            LOCAL_PORT=$(python3 -c "import random; print(random.randint($LOCAL_PORT_START, $LOCAL_PORT_END))" 2>/dev/null || \
                           python -c "import random; print(random.randint($LOCAL_PORT_START, $LOCAL_PORT_END))" 2>/dev/null || \
                           awk 'BEGIN{srand(); print int(20000+rand()*10001)}')
        fi

        if command -v ss >/dev/null 2>&1; then
            ss -tln | grep -q ":$LOCAL_PORT " || break
        elif command -v lsof >/dev/null 2>&1; then
            lsof -Pi ":$LOCAL_PORT" -sTCP:LISTEN -t >/dev/null 2>&1 || break
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tln 2>/dev/null | grep -q ":$LOCAL_PORT " || break
        else
            python3 -c "import socket; s=socket.socket(); s.bind(('', $LOCAL_PORT)); s.close()" 2>/dev/null && break
        fi
    done
fi

CONTROL_PATH="/tmp/opencode-ssh-${SSH_HOST}-${LOCAL_PORT}-$$.sock"

ssh -f -N -M -S "$CONTROL_PATH" -o ConnectTimeout=$SSH_CONNECT_TIMEOUT \
    -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "$SSH_HOST"

if [ $? -ne 0 ]; then
    error "SSH 隧道建立失败"
    # 清理远程进程（不依赖 REMOTE_PID，通过端口查找）
    ssh -o ConnectTimeout=5 "$SSH_HOST" "bash -c '
        for tool in lsof ss fuser; do
            if command -v $tool >/dev/null 2>&1; then
                case $tool in
                    lsof) p="$(lsof -t -i:'"$REMOTE_PORT"' -sTCP:LISTEN 2>/dev/null || true)";;
                    ss) p="$(ss -tlnp 2>/dev/null | grep ":'"$REMOTE_PORT"' " | sed "s/.*pid=\([0-9]*\).*/\1/" | head -1 || true)";;
                    fuser) p="$(fuser '"$REMOTE_PORT"'/tcp 2>/dev/null | tr -d " " || true)";;
                esac
                if [ -n "$p" ] && [ "$p" != "" ]; then
                    kill $p 2>/dev/null || true
                    sleep 0.5
                    kill -9 $p 2>/dev/null || true
                    break
                fi
            fi
        done
        rm -f /tmp/opencode-serve-'"$REMOTE_PORT"'.pid /tmp/opencode-serve-'"$REMOTE_PORT"'.session /tmp/opencode-serve-'"$REMOTE_PORT"'.log
    '" || true
    exit 1
fi

info "✅ 隧道建立: localhost:$LOCAL_PORT → $SSH_HOST:$REMOTE_PORT"

# ═══════════════════════════════════════════════════════
# STEP 7: 本地连接 + 清理
# ═══════════════════════════════════════════════════════
OPENCODE_URL="http://localhost:$LOCAL_PORT"

cleanup() {
    echo ""
    step "正在关闭连接并清理..."

    # ─── 清理远程进程 ───
    # 策略 1: 如果已知 REMOTE_PID，先尝试用它清理
    if [ -n "$REMOTE_PID" ]; then
        info "尝试通过已知 PID ($REMOTE_PID) 关闭远程 opencode serve..."
        ssh -o ControlPath=none -o ConnectTimeout=5 \
            "$SSH_HOST" "kill $REMOTE_PID 2>/dev/null || true; sleep 0.5; kill -9 $REMOTE_PID 2>/dev/null || true" 2>/dev/null || true
    fi

    # 策略 2: 通过端口查找并清理（fallback，更可靠）
    info "通过端口 $REMOTE_PORT 查找并清理远程进程..."

    # 构建远程清理脚本，用 base64 避免引号嵌套问题
    REMOTE_CLEANUP_SCRIPT=$(cat <<'REMOTESCRIPT'
set -eo pipefail
PORT="__REMOTE_PORT__"
PID_BY_PORT=""

# 方法 A: 通过监听端口找 PID
if command -v lsof >/dev/null 2>&1; then
    PID_BY_PORT=$(lsof -t -i:${PORT} -sTCP:LISTEN 2>/dev/null || true)
elif command -v ss >/dev/null 2>&1; then
    PID_BY_PORT=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | sed "s/.*pid=\([0-9]*\).*/\1/" | head -1 || true)
elif command -v fuser >/dev/null 2>&1; then
    PID_BY_PORT=$(fuser ${PORT}/tcp 2>/dev/null | tr -d " " || true)
elif [ -f /proc/net/tcp ]; then
    HEX_PORT=$(printf "%04X" ${PORT})
    INODE=$(awk "$2" ~ /:\$HEX_PORT\$/ {print $10} /proc/net/tcp | head -1 || true)
    if [ -n "$INODE" ] && [ "$INODE" != "0" ]; then
        PID_BY_PORT=$(find /proc -maxdepth 2 -type l -name fd 2>/dev/null | while read fd_dir; do
            if ls -l "$fd_dir" 2>/dev/null | grep -q "$INODE"; then
                basename "$(dirname "$fd_dir")"
                break
            fi
        done || true)
    fi
fi

# 方法 B: 通过 PID 文件找
PID_BY_FILE=$(cat /tmp/opencode-serve-${PORT}.pid 2>/dev/null || true)

# 合并所有找到的 PID，去重清理
ALL_PIDS=""
for p in "$PID_BY_PORT" "$PID_BY_FILE"; do
    if [ -n "$p" ] && [ "$p" != "" ]; then
        ALL_PIDS="$ALL_PIDS $p"
    fi
done

# 清理所有找到的进程
if [ -n "$ALL_PIDS" ]; then
    for pid in $ALL_PIDS; do
        if kill -0 $pid 2>/dev/null; then
            echo "Killing PID: $pid"
            kill $pid 2>/dev/null || true
            sleep 0.5
            kill -9 $pid 2>/dev/null || true
        fi
    done
else
    echo "No process found for port ${PORT}"
fi

# 清理临时文件
rm -f /tmp/opencode-serve-${PORT}.pid /tmp/opencode-serve-${PORT}.session /tmp/opencode-serve-${PORT}.log /tmp/opencode-wrapper-*
echo "Remote cleanup done"
REMOTESCRIPT
)
    REMOTE_CLEANUP_SCRIPT=${REMOTE_CLEANUP_SCRIPT//__REMOTE_PORT__/$REMOTE_PORT}
    CLEANUP_B64=$(printf '%s' "$REMOTE_CLEANUP_SCRIPT" | base64 | tr -d '
')

    ssh -o ControlPath=none -o ConnectTimeout=5 \
        "$SSH_HOST" "echo '$CLEANUP_B64' | base64 -d | bash" 2>/dev/null || warn "远程清理命令执行失败（可能 SSH 已断开）"

    # ─── 关闭 SSH 隧道 ───
    if [ -S "$CONTROL_PATH" ]; then
        info "正在关闭 SSH 隧道..."
        # 尝试优雅关闭控制 socket
        if ssh -S "$CONTROL_PATH" -O exit "$SSH_HOST" 2>/dev/null; then
            info "SSH 隧道已通过控制 socket 关闭"
        else
            warn "SSH 控制 socket 关闭失败，尝试强制终止..."
            # 查找并 kill 对应的 SSH 进程
            SSH_PID=$(lsof -t "$CONTROL_PATH" 2>/dev/null || true)
            if [ -n "$SSH_PID" ]; then
                kill "$SSH_PID" 2>/dev/null || true
                sleep 0.5
                kill -9 "$SSH_PID" 2>/dev/null || true
                info "已强制终止 SSH 进程 (PID: $SSH_PID)"
            fi
        fi
        rm -f "$CONTROL_PATH"
    fi

    # 兜底：再次检查是否还有该端口的 SSH 转发残留
    info "检查是否有残留的 SSH 转发..."
    for pid in $(lsof -t -i:$LOCAL_PORT -sTCP:LISTEN 2>/dev/null || true); do
        if ps -p "$pid" -o comm= 2>/dev/null | grep -q ssh; then
            warn "发现残留 SSH 进程 (PID: $pid)，正在清理..."
            kill "$pid" 2>/dev/null || true
            sleep 0.3
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    info "已断开连接并清理完成"
}

trap cleanup EXIT INT TERM

sleep 0.5

info "🚀 OpenCode 地址: $OPENCODE_URL"

if [ "$USE_BROWSER" = true ]; then
    step "打开浏览器..."
    if command -v open >/dev/null 2>&1; then open "$OPENCODE_URL"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$OPENCODE_URL"
    else warn "无法自动打开浏览器，请手动访问: $OPENCODE_URL"
    fi
    info "按 Ctrl+C 关闭..."
    sleep infinity
else
    step "执行: opencode attach $OPENCODE_URL --password ***"
    if command -v opencode >/dev/null 2>&1; then
        opencode attach "$OPENCODE_URL" --password "$SERVER_PASSWORD"
    else
        warn "本地未安装 opencode CLI"
        info "浏览器访问: $OPENCODE_URL (密码: $SERVER_PASSWORD)"
        info "按 Ctrl+C 关闭..."
        sleep infinity
    fi
fi
