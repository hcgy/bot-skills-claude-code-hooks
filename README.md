# Claude Code Stop Hook — 任务完成自动回调

当 Claude Code（含 Agent Teams）完成任务后，自动：
- 将结果写入 JSON 文件
- 发送飞书通知到指定用户
- 写入 pending-wake 文件供 AGI 主会话读取

## 架构

```
dispatch-claude-code.sh │
├─ 写入 task-meta.json（任务名、目标用户）
├─ 启动 Claude Code（via claude_code_run.py）
└─ Agent Teams lead + sub-agents 运行
   └─ Claude Code 完成 → Stop Hook 自动触发
      ├─ notify-agi.sh 执行：
      │   ├─ 读取 task-meta.json + task-output.txt
      │   ├─ 写入 latest.json（完整结果）
      │   ├─ openclaw message send → 飞书
      │   └─ 写入 pending-wake.json
      └─ AGI heartbeat 读取 pending-wake.json（备选）
```

## 文件说明

| 文件 | 位置 | 作用 |
|------|------|------|
| claude-code-hooks/notify-agi.sh | ~/.claude/hooks/ | Stop Hook 脚本 |
| claude-code-hooks/dispatch.sh | ~/.openclaw/skills/claude-code-dispatch/ | 一键派发任务 |
| scripts/claude_code_run.py | ~/.openclaw/skills/claude-code-dispatch/scripts/ | Claude Code PTY 运行器 |
| claude-settings.json | ~/.claude/settings.json | Claude Code 配置（注册 hook） |

## 使用方法

### 基础任务

```bash
dispatch-claude-code.sh \
  -p "实现一个 Python 爬虫" \
  -n "my-scraper" \
  -f "user:ou_xxx" \
  --permission-mode "bypassPermissions" \
  --workdir "/path/to/project"
```

### Agent Teams 任务

```bash
dispatch-claude-code.sh \
  -p "重构整个项目的测试" \
  -n "test-refactor" \
  -f "user:ou_xxx" \
  --agent-teams \
  --teammate-mode auto \
  --permission-mode "bypassPermissions" \
  --workdir "/path/to/project"
```

### OpenClaw Skill 方式

```bash
/claude-code-dispatch -f "user:ou_xxx" -p "任务描述" --workdir "/path"
```

## 参数

| 参数 | 说明 |
|------|------|
| -p, --prompt | 任务提示（必需） |
| -n, --name | 任务名称（用于跟踪） |
| -f, --feishu | 飞书用户 ID（结果自动发送） |
| -w, --workdir | 工作目录 |
| --agent-teams | 启用 Agent Teams |
| --teammate-mode | Agent Teams 模式 (auto/in-process/tmux) |
| --permission-mode | 权限模式 |
| --allowed-tools | 允许的工具列表 |

## Hook 配置

在 `~/.claude/settings.json` 中注册：

```json
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/notify-agi.sh", "timeout": 10}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/notify-agi.sh", "timeout": 10}]}]
  }
}
```

## 防重复机制

Hook 在 Stop 和 SessionEnd 都会触发。脚本使用 `.hook-lock` 文件去重：
- 30秒内重复触发自动跳过
- 只处理第一个事件（通常是 Stop）

## 结果文件

任务完成后，结果写入 `/home/dministrator/.openclaw/data/claude-code-results/latest.json`：

```json
{
  "session_id": "...",
  "timestamp": "2026-02-10T01:02:33+00:00",
  "task_name": "my-task",
  "feishu_target": "user:ou_xxx",
  "output": "...",
  "status": "done"
}
```

## 文件路径

- Hook 脚本: `~/.claude/hooks/notify-agi.sh`
- dispatch 脚本: `~/.openclaw/skills/claude-code-dispatch/dispatch.sh`
- Runner: `~/.openclaw/skills/claude-code-dispatch/scripts/claude_code_run.py`
- 结果目录: `~/.openclaw/data/claude-code-results/`
- OpenClaw Skill: `~/.openclaw/skills/claude-code-dispatch/`

## 参考

- 原文仓库：https://github.com/win4r/claude-code-hooks
