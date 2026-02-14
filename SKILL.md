---
name: claude-code-dispatch
description: Dispatch tasks to Claude Code with zero polling using Hooks callback pattern (Dispatch & Forget).
metadata:
  {
    "openclaw": { "emoji": "🚀", "requires": { "anyBins": ["claude"] } },
  }
command-dispatch: tool
command-tool: bash
command-arg-mode: raw
background: true
---

# Claude Code Dispatch Skill

Dispatch tasks to Claude Code with zero polling and auto-callback via Hooks.

## Concept

This skill implements the **Dispatch & Forget** pattern from [Agent Teams + Hooks](https://www.aivi.fyi/aiagents/OpenClaw-Agent-Teams):

```
User → Me → /claude-code-dispatch → Claude Code → Hook → Wakes Me → User
                                                    ↑
                                        Claude Code does the work
```

**I am the coordinator. Claude Code does the development.**

## Usage

```
/claude-code-dispatch -f "user:ou_xxx" -p "你的任务描述" --workdir "项目路径"
```

### Parameters

| Parameter | Alias | Description | Required |
|-----------|-------|-------------|----------|
| `-f` | `--feishu` | Feishu user ID for notification (format: `user:ou_xxx`) | Yes |
| `-p` | `--prompt` | Task prompt/description | Yes |
| `-n` | `--name` | Task name (optional, auto-generated if omitted) | No |
| `--workdir` | `-w` | Working directory for Claude Code | Recommended |
| `--agent-teams` | | Enable Agent Teams (parallel agents) | No |
| `--teammate-mode` | | Agent Teams display mode: `auto`, `in-process`, or `tmux` | No |
| `--permission-mode` | | Claude Code permission mode: `bypassPermissions`, `resume`, etc. | No |

### Examples

**Simple task:**
```
/claude-code-dispatch -f "user:ou_xxx" -p "实现用户登录功能"
```

**With working directory:**
```
/claude-code-dispatch -f "user:ou_xxx" -p "修复登录 bug" --workdir "/path/to/project"
```

**Agent Teams (parallel):**
```
/claude-code-dispatch -f "user:ou_xxx" --agent-teams -p "用 Team 方案重构整个项目"
```

## How It Works

1. **Dispatch**: This skill runs `dispatch.sh` in background
2. **Execute**: `dispatch.sh` calls Claude Code to do the work
3. **Callback**: When Claude Code finishes, it triggers the Stop Hook
4. **Notify**: Hook reads results, sends Feishu notification, wakes me up
5. **Report**: I read the results and report back to you

## Results

After task completion:
- Check results: `/claude-code-results`
- Results saved to: `~/.openclaw/data/claude-code-results/latest.json`

## Notes

- **Non-blocking**: I don't wait for Claude Code to complete
- **Auto-notify**: You get notified via Feishu when done
- **Zero polling**: Uses Hooks pattern, no token-wasting status checks
