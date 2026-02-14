#!/bin/bash
# Claude Code Stop Hook: 任务完成后通知 AGI

set -uo pipefail

LOG="/home/dministrator/.openclaw/data/claude-code-results/hook.log"
RESULT_DIR="/home/dministrator/.openclaw/data/claude-code-results"
META_FILE="${RESULT_DIR}/task-meta.json"
OPENCLAW_BIN="/home/dministrator/.npm-global/bin/openclaw"

mkdir -p "$RESULT_DIR"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

log "=== Hook fired ==="

# ---- 读 stdin ----
INPUT=""
if [ -t 0 ]; then
    log "stdin is tty, skip"
elif [ -e /dev/stdin ]; then
    INPUT=$(timeout 2 cat /dev/stdin 2>/dev/null || true)
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")

log "session=$SESSION_ID cwd=$CWD event=$EVENT"

# ---- 读取任务输出 ----
OUTPUT=""

# 等待 tee 管道 flush
sleep 1

if [ -f "$RESULT_DIR/task-output.txt" ] && [ -s "$RESULT_DIR/task-output.txt" ]; then
    OUTPUT=$(tail -c 4000 "$RESULT_DIR/task-output.txt")
    log "Output from task-output.txt (${#OUTPUT} chars)"
fi

if [ -z "$OUTPUT" ] && [ -f "/tmp/claude-code-output.txt" ] && [ -s "/tmp/claude-code-output.txt" ]; then
    OUTPUT=$(tail -c 4000 /tmp/claude-code-output.txt)
    log "Output from /tmp fallback (${#OUTPUT} chars)"
fi

if [ -z "$OUTPUT" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
    FILES=$(ls -1t "$CWD" 2>/dev/null | head -20 | tr '\n' ', ')
    OUTPUT="Working dir: ${CWD}\nFiles: ${FILES}"
    log "Output from dir listing"
fi

# ---- 读取任务元数据 ----
TASK_NAME="unknown"
TELEGRAM_GROUP=""
FEISHU_TARGET=""
AUTO_PUSH="false"
WORKDIR=""

if [ -f "$META_FILE" ]; then
    TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
    TELEGRAM_GROUP=$(jq -r '.telegram_group // ""' "$META_FILE" 2>/dev/null || echo "")
    FEISHU_TARGET=$(jq -r '.feishu_target // ""' "$META_FILE" 2>/dev/null || echo "")
    AUTO_PUSH=$(jq -r '.auto_push // "false"' "$META_FILE" 2>/dev/null || echo "false")
    WORKDIR=$(jq -r '.workdir // ""' "$META_FILE" 2>/dev/null || echo "")
    log "Meta: task=$TASK_NAME group=$TELEGRAM_GROUP feishu=$FEISHU_TARGET auto_push=$AUTO_PUSH workdir=$WORKDIR"
fi

# ---- 过滤终端控制字符 ----
filter_ansi() {
    echo "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
                    -e 's/\^\[[0-9;]*[a-zA-Z]//g' \
                    -e 's/\[?[0-9]*[a-zA-Z]//g' \
                    -e 's/\]9;4;0;//g' \
                    -e 's/\a//g'
}

# ---- 检测任务状态（成功/失败） ----
detect_status() {
    local output="$1"
    # 检测错误关键词
    if echo "$output" | grep -qiE '(error|failed|failure|exception|denied|timeout|中断|失败|错误|异常)'; then
        echo "failed"
    else
        echo "success"
    fi
}

# ---- 发送飞书纯文本消息 ----
send_feishu() {
    local target="$1"
    local msg="$2"

    log "send_feishu: target=$target"

    # 飞书是国内服务，直连不走代理
    export no_proxy="localhost,127.0.0.1,feishu.cn,open.feishu.cn"

    local result
    result=$("$OPENCLAW_BIN" message send \
        --channel feishu \
        --target "$target" \
        --message "$msg" 2>&1)
    local exit_code=$?
    log "Result: exit=$exit_code, output=$result"

    if [ $exit_code -eq 0 ]; then
        log "Feishu text sent successfully"
        return 0
    fi

    log "Feishu send failed (exit=$exit_code)"
    return 1
}

OUTPUT=$(filter_ansi "$OUTPUT")

# ---- 写入结果 JSON ----
jq -n \
    --arg sid "$SESSION_ID" \
    --arg ts "$(date -Iseconds)" \
    --arg cwd "$CWD" \
    --arg event "$EVENT" \
    --arg output "$OUTPUT" \
    --arg task "$TASK_NAME" \
    --arg feishu "$FEISHU_TARGET" \
    '{session_id: $sid, timestamp: $ts, cwd: $cwd, event: $event, output: $output, task_name: $task, feishu_target: $feishu, status: "done"}' \
    > "${RESULT_DIR}/latest.json" 2>/dev/null

log "Wrote latest.json"

# ---- 自动 Git Push ----
if [ "$AUTO_PUSH" = "true" ] && [ -n "$WORKDIR" ] && [ -d "$WORKDIR/.git" ]; then
    log "Auto push enabled, starting git push..."
    (
        cd "$WORKDIR"
        # 设置代理
        WSL_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
        export http_proxy="http://${WSL_IP}:4780"
        export https_proxy="http://${WSL_IP}:4780"
        export no_proxy="localhost,127.0.0.1"

        # 检查是否有变更
        if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
            echo "[$(date -Iseconds)] Auto push: No changes to commit" >> "$LOG"
            exit 0
        fi

        # 添加所有变更
        git add -A 2>/dev/null || true

        # 自动提交
        git commit -m "Auto commit by Claude Code: $TASK_NAME" 2>/dev/null || true

        # 推送到远程
        if git push origin HEAD 2>&1; then
            echo "[$(date -Iseconds)] Auto push: Successfully pushed" >> "$LOG"
        else
            echo "[$(date -Iseconds)] Auto push: Failed to push" >> "$LOG"
        fi
    ) &
    log "Auto push started in background"
else
    log "Auto push skipped: auto_push=$AUTO_PUSH, workdir=$WORKDIR"
fi

# ---- 只在有输出时发送飞书消息 ----
if [ -n "$FEISHU_TARGET" ] && [ -x "$OPENCLAW_BIN" ] && [ -n "$OUTPUT" ]; then
    # 检测任务状态
    STATUS=$(detect_status "$OUTPUT")
    SUMMARY=$(echo "$OUTPUT" | tail -c 800 | tr '\n' ' ' | sed 's/  */ /g')

    # 纯文本消息格式
    MSG="任务: ${TASK_NAME}
状态: ${STATUS}
结果: ${SUMMARY:0:500}"

    # 后台发送，不阻塞 Hook
    (
        export no_proxy="localhost,127.0.0.1,feishu.cn,open.feishu.cn"
        if send_feishu "$FEISHU_TARGET" "$MSG"; then
            echo "[$(date -Iseconds)] Background: Feishu sent" >> "$LOG"
        else
            echo "[$(date -Iseconds)] Background: Feishu failed" >> "$LOG"
        fi
    ) &
else
    log "Skipped sending - no output or no target"
fi

# ---- 唤醒 AGI 会话 ----
WAKE_FILE="${RESULT_DIR}/pending-wake.json"
jq -n \
    --arg task "$TASK_NAME" \
    --arg feishu "$FEISHU_TARGET" \
    --arg ts "$(date -Iseconds)" \
    --arg summary "$(echo "$OUTPUT" | head -c 500)" \
    --arg processed "false" \
    '{task_name: $task, feishu_target: $feishu, timestamp: $ts, summary: $summary, processed: false}' \
    > "$WAKE_FILE" 2>/dev/null

log "Wrote pending-wake.json"
log "=== Hook completed ==="
exit 0
