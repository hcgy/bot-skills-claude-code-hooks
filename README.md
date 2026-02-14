# Claude Code Stop Hook — 任务完成自动回调

> 基于 OpenClaw + Claude Code 的零轮询开发方案

## 核心思想

**派发后不管，完成自动通知**

```
用户 → OpenClaw → dispatch → Claude Code (后台) → Hook → 飞书通知 → 用户
```

**优势**：
- OpenClaw 不需要轮询，不消耗额外 tokens
- Claude Code 在后台独立运行
- 任务完成后自动推送通知到飞书

---

当 Claude Code（含 Agent Teams）完成任务后，自动：
- 将结果写入 JSON 文件
- 发送飞书通知到指定用户
- 写入 pending-wake 文件供 AGI 主会话读取

## 架构

```
dispatch.sh │
├─ 写入 task-meta.json（任务名、目标用户）
├─ 启动 Claude Code（via claude_code_run.py）
└─ Claude Code 运行
   └─ 完成 → SessionEnd Hook 触发
      ├─ notify-agi.sh 执行（后台发送飞书）：
      │   ├─ 读取 task-meta.json + task-output.txt
      │   ├─ 写入 latest.json（完整结果）
      │   ├─ openclaw message send → 飞书（后台）
      │   └─ 写入 pending-wake.json
      └─ AGI 主会话读取结果
```

## 文件说明

| 文件 | 位置 | 作用 |
|------|------|------|
| claude-code-hooks/notify-agi.sh | ~/.claude/hooks/ | SessionEnd Hook 脚本 |
| claude-code-hooks/dispatch.sh | ~/.openclaw/skills/claude-code-dispatch/ | 一键派发任务 |
| scripts/claude_code_run.py | ~/.openclaw/skills/claude-code-dispatch/scripts/ | Claude Code PTY 运行器 |
| claude-settings.json | ~/.claude/settings.json | Claude Code 配置（注册 hook） |

## 使用方法

### 基础任务

```bash
dispatch.sh -p "实现一个 Python 爬虫" -n "my-scraper" -f "user:ou_xxx" -w "/path/to/project"
```

### Agent Teams 任务

```bash
dispatch.sh -p "重构整个项目的测试" -n "test-refactor" -f "user:ou_xxx" --agent-teams -w "/path/to/project"
```

### OpenClaw Skill 方式

```bash
/claude-code-dispatch -f "user:ou_xxx" -p "任务描述" --workdir "/path"
```

## 参数

| 参数 | 说明 |
|------|------|
| -p, --prompt | 任务提示（必需） |
| -n, --name | 任务名称 |
| -f, --feishu | 飞书用户 ID（结果自动发送） |
| -w, --workdir | 工作目录 |
| --agent-teams | 启用 Agent Teams |
| --permission-mode | 权限模式（默认 bypassPermissions） |

## Hook 配置

在 `~/.claude/settings.json` 中注册（只用 SessionEnd）：

```json
{
  "hooks": {
    "Stop": [],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/dministrator/.claude/hooks/notify-agi.sh"
          }
        ]
      }
    ]
  }
}
```

**注意**：
- 只使用 SessionEnd Hook（Stop Hook 触发时输出文件可能未写完）
- 飞书消息发送在后台执行，避免超时

## 结果文件

任务完成后，结果写入 `~/.openclaw/data/claude-code-results/latest.json`：

```json
{
  "session_id": "...",
  "timestamp": "2026-02-14T18:08:03+08:00",
  "task_name": "adhoc-xxx",
  "feishu_target": "user:ou_xxx",
  "output": "已创建文件...",
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
- 本仓库：https://github.com/hcgy/bot-skills-claude-code-hooks
