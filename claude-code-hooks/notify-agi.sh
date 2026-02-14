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

if [ -f "$META_FILE" ]; then
    TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
    TELEGRAM_GROUP=$(jq -r '.telegram_group // ""' "$META_FILE" 2>/dev/null || echo "")
    FEISHU_TARGET=$(jq -r '.feishu_target // ""' "$META_FILE" 2>/dev/null || echo "")
    log "Meta: task=$TASK_NAME group=$TELEGRAM_GROUP feishu=$FEISHU_TARGET"
fi

# ---- 过滤终端控制字符 ----
filter_ansi() {
    echo "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
                    -e 's/\^\[[0-9;]*[a-zA-Z]//g' \
                    -e 's/\[?[0-9]*[a-zA-Z]//g' \
                    -e 's/\]9;4;0;//g' \
                    -e 's/\a//g'
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

# ---- 只在有输出时发送飞书消息 ----
if [ -n "$FEISHU_TARGET" ] && [ -x "$OPENCLAW_BIN" ] && [ -n "$OUTPUT" ]; then
    SUMMARY=$(echo "$OUTPUT" | tail -c 1000)
    MSG="Claude Code 任务完成

任务: ${TASK_NAME}

结果:
${SUMMARY:0:800}"
    
    if "$OPENCLAW_BIN" message send \
        --channel feishu \
        --target "$FEISHU_TARGET" \
        --message "$MSG" 2>/dev/null; then
        log "Sent Feishu message"
    else
        log "Feishu send failed"
    fi
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
