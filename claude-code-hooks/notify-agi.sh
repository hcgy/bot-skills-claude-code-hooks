#!/bin/bash
# Claude Code Stop Hook: 任务完成后通知 AGI

set -uo pipefail

LOG="/home/dministrator/.openclaw/data/claude-code-results/hook.log"
RESULT_DIR="/home/dministrator/.openclaw/data/claude-code-results"
META_FILE="${RESULT_DIR}/task-meta.json"
OPENCLAW_BIN="/home/dministrator/.npm-global/bin/openclaw"

# MANUAL_CALL 模式：手动调用，跳过 stdin 读取，从文件获取完整输出
MANUAL_MODE=false
if [ "${MANUAL_CALL:-}" = "1" ]; then
    MANUAL_MODE=true
    echo "[$(date -Iseconds)] MANUAL_CALL mode enabled" >> "$LOG"
fi

mkdir -p "$RESULT_DIR"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

log "=== Hook fired ==="

# ---- 读 stdin ----
INPUT=""
if [ "$MANUAL_MODE" = true ]; then
    log "MANUAL_MODE: skipping stdin"
elif [ -t 0 ]; then
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

# 如果还是空的，尝试从 latest.json 读取
if [ -z "$OUTPUT" ] && [ -f "${RESULT_DIR}/latest.json" ]; then
    OUTPUT=$(jq -r '.output // ""' "${RESULT_DIR}/latest.json" 2>/dev/null | tail -c 4000)
    if [ -n "$OUTPUT" ]; then
        log "Output from latest.json (${#OUTPUT} chars)"
    fi
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
TASK_PROMPT=""
STARTED_AT=""
TELEGRAM_GROUP=""
FEISHU_TARGET=""

if [ -f "$META_FILE" ]; then
    TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
    TASK_PROMPT=$(jq -r '.prompt // ""' "$META_FILE" 2>/dev/null || echo "")
    STARTED_AT=$(jq -r '.started_at // ""' "$META_FILE" 2>/dev/null || echo "")
    TELEGRAM_GROUP=$(jq -r '.telegram_group // ""' "$META_FILE" 2>/dev/null || echo "")
    FEISHU_TARGET=$(jq -r '.feishu_target // ""' "$META_FILE" 2>/dev/null || echo "")
    log "Meta: task=$TASK_NAME group=$TELEGRAM_GROUP feishu=$FEISHU_TARGET"
fi

# 提取 prompt 前20字作为标题（按字符截断，避免中文被截断）
TITLE=$(echo "$TASK_PROMPT" | sed 's/[^[:print:]]//g' | awk '{print substr($0,1,20)}')

# ---- 过滤终端控制字符 ----
filter_ansi() {
    echo "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
                    -e 's/\^\[[0-9;]*[a-zA-Z]//g' \
                    -e 's/\[?[0-9]*[a-zA-Z]//g' \
                    -e 's/\]9;4;0;//g' \
                    -e 's/\a//g'
}

# ---- 过滤 Claude Code 调试日志 ----
# 只过滤明确的调试前缀，保留关键输出（如任务结果、commit信息等）
filter_debug_logs() {
    echo "$1" | sed -e '/^\[BashTool\] Pre-flight check/d' \
                    -e '/^\[plugins\]:/d' \
                    -e '/^\[info\]:/d' \
                    -e '/ANTHROPIC_LOG/d' \
                    -e '/^$/d' \
                    -e '/^[[:space:]]*$/d' \
        | awk '!seen[$0]++'  # 去除重复行（保留首次出现的行）
}

# ---- 检测任务状态（成功/失败）----
detect_status() {
    local output="$1"
    # 检测致命错误关键词（更精确）
    if echo "$output" | grep -qiE '(fatal|crash|abort|cannot|unable to|denied|permission denied|command not found|not found|404|500|connection refused)'; then
        echo "failed"
    else
        echo "success"
    fi
}

# ---- 发送飞书卡片消息 ----
send_feishu_card() {
    local target="$1"
    local title="$2"
    local status="$3"
    local started="$4"
    local solved="$5"
    local result_text="$6"

    log "send_feishu_card: target=$target title=$title"

    # 飞书是国内服务，直连不走代理
    export no_proxy="localhost,127.0.0.1,feishu.cn,open.feishu.cn"

    # 构建飞书卡片 JSON
    # 清理结果文本中的特殊字符
    result_text=$(echo "$result_text" | sed 's/"/\\"/g; s/\x1b\[[0-9;]*[a-zA-Z]//g; s/```//g' | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-500)

    # 根据状态设置颜色和图标
    if [ "$status" = "success" ]; then
        status_icon="✅"
        status_color="green"
    else
        status_icon="❌"
        status_color="red"
    fi

    # 构建卡片 JSON
    CARD_JSON=$(cat <<EOF
{
  "config": {
    "wide_screen_mode": true
  },
  "header": {
    "title": {
      "tag": "plain_text",
      "content": "$status_icon 任务完成: $title"
    },
    "template": "$status_color"
  },
  "elements": [
    {
      "tag": "div",
      "text": {
        "tag": "lark_md",
        "content": "**状态:** $status_icon $status"
      }
    },
    {
      "tag": "div",
      "text": {
        "tag": "lark_md",
        "content": "**提出时间:** $started"
      }
    },
    {
      "tag": "div",
      "text": {
        "tag": "lark_md",
        "content": "**完成时间:** $solved"
      }
    },
    {
      "tag": "hr"
    },
    {
      "tag": "div",
      "text": {
        "tag": "lark_md",
        "content": "**结果:**\n$result_text"
      }
    }
  ]
}
EOF
)

    local result
    # 同时发送 card 和 message（fallback），确保至少一个能成功
    result=$("$OPENCLAW_BIN" message send \
        --channel feishu \
        --target "$target" \
        --card "$CARD_JSON" \
        --message "📋 任务完成: $title" 2>&1)
    local exit_code=$?
    log "Result: exit=$exit_code, output=$result"

    if [ $exit_code -eq 0 ]; then
        log "Feishu card sent successfully"
        return 0
    fi

    log "Feishu card send failed (exit=$exit_code), falling back to text"
    # 回退到纯文本
    send_feishu_text "$target" "$title\n状态: $status\n提出: $started\n完成: $solved\n结果: $result_text"
    return $?
}

# ---- 发送飞书纯文本消息（回退用）----
send_feishu_text() {
    local target="$1"
    local msg="$2"

    log "send_feishu_text: target=$target"

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
OUTPUT=$(filter_debug_logs "$OUTPUT")

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
if true; then # DISABLED:  && [ -x "$OPENCLAW_BIN" ] && [ -n "$OUTPUT" ]; then
    # 检测任务状态
    STATUS=$(detect_status "$OUTPUT")
    SUMMARY=$(echo "$OUTPUT" | tail -c 800 | tr '\n' ' ' | sed 's/  */ /g')

    # 简洁清晰的纯文本消息格式 - 单行优先，避免格式问题
    if [ "$STATUS" = "success" ]; then
        STATUS_TEXT="[OK]"
    else
        STATUS_TEXT="[FAIL]"
    fi

    # 提取关键结果（取最后几行的核心内容，最多150字符），去除代码块
    KEY_RESULT=$(echo "$OUTPUT" | tail -20 | head -5 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-150)
    # 进一步清理可能的特殊字符和代码块符号
    # Remove duplicate bullets
    KEY_RESULT=$(echo "$KEY_RESULT" | sed 's/^- - /- /g; s/^-- /- /g')
KEY_RESULT=$(echo "$KEY_RESULT" | sed 's/"/-/g; s/\x1b\[[0-9;]*[a-zA-Z]//g; s/```//g; s/\*\*//g; s/\*//g')

    # 格式化时间（只显示时分）
    if [ -n "$STARTED_AT" ]; then
        STARTED_DISPLAY=$(echo "$STARTED_AT" | sed 's/.*T//' | cut -d':' -f1,2)
    else
        STARTED_DISPLAY="未知"
    fi
    SOLVED_TIME=$(date "+%H:%M")

    # 提取关键结果，每行一条Bullet，去除代码块符号，并去重
    KEY_LINES=$(echo "$OUTPUT" | tail -20 | head -10 | grep -v '^$' | head -5 | sed 's/"/-/g; s/\x1b\[[0-9;]*[a-zA-Z]//g; s/```//g' | sed 's/^/- /' | awk '!seen[$0]++')

    # 如果 KEY_LINES 为空，用 prompt 作为结果
    if [ -z "$KEY_LINES" ] && [ -n "$TASK_PROMPT" ]; then
        KEY_LINES="- 任务: $TASK_PROMPT"
    fi

    # 组装通知消息 - 使用优化的纯文本格式
    if [ "$STATUS" = "success" ]; then
        STATUS_ICON="✅"
    else
        STATUS_ICON="❌"
    fi

    MSG="📋 任务完成: ${TITLE}

${STATUS_ICON} 状态: ${STATUS}
⏰ 提出: ${STARTED_DISPLAY}
⏰ 完成: ${SOLVED_TIME}

📝 结果:
${KEY_LINES}"

    # 同步发送
    export no_proxy="localhost,127.0.0.1,feishu.cn,open.feishu.cn"
    if send_feishu_text "$FEISHU_TARGET" "$MSG"; then
        log "Feishu formatted message sent successfully"
    else
        log "Feishu message failed"
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
    # Wake up OpenClaw agent
    "$OPENCLAW_BIN" gateway wake --mode next-heartbeat 2>/dev/null || true
log "=== Hook completed ==="
exit 0
