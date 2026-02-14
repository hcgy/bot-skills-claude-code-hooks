# Claude Code Hook — 任务完成自动回调

> 基于 OpenClaw + Claude Code 的零轮询开发方案

## 核心思想

**派发后不管，完成自动通知**

```
用户 → OpenClaw → dispatch → Claude Code (后台) → Hook → 飞书通知 → 用户
```

### 为什么这样做？

| 传统方式 | 我们的方式 |
|---------|-----------|
| OpenClaw 等待 Claude Code 完成 | OpenClaw 只负责派发，不等待 |
| 占用大量 Context Tokens | 不消耗额外 tokens |
| 等待时间长，阻塞其他任务 | OpenClaw 可以中途接收其他任务 |
| 大任务需要一直保持会话 | Claude Code 后台独立运行 |
| 无法调用 MCP 能力 | 支持 MCP 能力调用 |

**重要**：只要 OpenClaw 调用 Claude Code，必须使用这种派发方式！

传统方式（直接调用）弊端：
- 占用大量 Context Tokens
- 阻塞 OpenClaw 无法处理其他任务
- 无法调用 MCP 能力
- 大任务会导致会话过长

**核心优势**：
1. **派发模式**：OpenClaw 把任务派发给 Claude Code，立即返回
2. **零轮询**：不需要反复检查任务状态
3. **无阻塞**：OpenClaw 可以继续处理其他任务
4. **自动回调**：Claude Code 完成后自动通知

---

## 项目结构

```
bot-skills-claude-code-hooks/
├── README.md                      # 项目说明
├── claude-settings.json           # Claude Code 配置示例
├── claude-code-hooks/
│   ├── notify-agi.sh              # SessionEnd Hook 脚本
│   └── dispatch.sh                # 任务派发脚本
└── scripts/
    └── claude_code_run.py          # Claude Code PTY 运行器
```

---

---

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/hcgy/bot-skills-claude-code-hooks.git
cd bot-skills-claude-code-hooks
```

### 2. 安装 Skill

```bash
# 复制 dispatch skill
cp -r claude-code-dispatch ~/.openclaw/skills/

# 或者手动创建链接
mkdir -p ~/.openclaw/skills/claude-code-dispatch
cp dispatch.sh ~/.openclaw/skills/claude-code-dispatch/
cp -r scripts ~/.openclaw/skills/claude-code-dispatch/
cp SKILL.md ~/.openclaw/skills/claude-code-dispatch/

# 重启 OpenClaw
openclaw gateway restart
```

### 3. 配置 Claude Code Hook

```bash
# 复制 Hook 脚本
cp claude-code-hooks/notify-agi.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/notify-agi.sh

# 复制 Claude Code 配置（需要替换为你的 API Key）
cp claude-settings.json ~/.claude/settings.json
# 注意：需要在 settings.json 中填入你的 ANTHROPIC_AUTH_TOKEN
```

### 4. 开始使用

```bash
# 派发任务
/claude-code-dispatch -f "user:飞书用户ID" -p "写一个 Python 计算器" --workdir "/项目路径"
```

---

## 工作原理

### 1. 任务派发流程

```
1. 用户告诉 OpenClaw 一个开发任务
2. OpenClaw 调用 dispatch 脚本
3. dispatch 启动 Claude Code（后台运行）
4. OpenClaw 立即返回，不阻塞
5. 用户可以继续做其他事
```

### 2. 通知回调流程

```
Claude Code 完成任务
       ↓
   自动触发 SessionEnd Hook
       ↓
   notify-agi.sh 执行：
   ├─ 读取 task-output.txt
   ├─ 写入 latest.json
   ├─ 后台发送飞书通知
   └─ 写入 pending-wake.json
       ↓
   用户收到飞书通知
```

### 3. 为什么只用 SessionEnd Hook？

Claude Code 有两个生命周期点：

| Hook 名称 | 触发时机 | 说明 |
|-----------|---------|------|
| **Stop** | 生成停止时 | 可能输出未完成 |
| **SessionEnd** | 会话结束时 | 输出完整 |

**问题**：Stop Hook 触发时，输出文件可能还没写完。

**解决**：只用 SessionEnd Hook，飞书消息后台发送避免超时。

### 4. 大任务会有问题吗？

**不会！** dispatch.sh 没有超时设置，会一直等待 Claude Code 完成：
- 简单任务：几分钟完成
- 大型任务：几小时也会等待
- 任务完成后自动触发 Hook
- Hook 后台发送飞书通知

---

## dispatch 参数

| 参数 | 简写 | 说明 | 必需 |
|------|------|------|------|
| --feishu | -f | 飞书用户 ID | ✅ |
| --prompt | -p | 任务描述 | ✅ |
| --workdir | -w | 工作目录 | 可选 |
| --permission-mode | - | 权限模式（默认 bypassPermissions） | 可选 |
| --agent-teams | - | 启用 Agent Teams | 可选 |
| --name | -n | 任务名称 | 可选 |

### 示例

```bash
# 简单任务
/claude-code-dispatch -f "user:ou_xxx" -p "写一个 Hello World"

# 指定工作目录
/claude-code-dispatch -f "user:ou_xxx" -p "写一个 Flask API" -w "/home/user/project"

# Agent Teams 模式（复杂任务）
/claude-code-dispatch -f "user:ou_xxx" --agent-teams -p "重构整个前端项目"
```

---

## 核心文件说明

### notify-agi.sh

位置：`~/.claude/hooks/notify-agi.sh`

功能：
1. 读取 Claude Code 的输出（task-output.txt）
2. 读取任务元数据（task-meta.json）
3. 写入完整结果（latest.json）
4. 后台发送飞书通知
5. 写入 pending-wake.json

### dispatch.sh

位置：`~/.openclaw/skills/claude-code-dispatch/dispatch.sh`

功能：
1. 写入任务元数据（task-meta.json）
2. 清空上次输出
3. 启动 Claude Code（通过 claude_code_run.py）
4. 等待完成

### claude_code_run.py

位置：`~/.openclaw/skills/claude-code-dispatch/scripts/claude_code_run.py`

功能：
- 在 PTY 中运行 Claude Code
- 支持 Agent Teams
- 支持各种参数

---

## 结果文件

任务完成后，结果写入 `~/.openclaw/data/claude-code-results/latest.json`：

```json
{
  "session_id": "",
  "timestamp": "2026-02-14T18:08:03+08:00",
  "task_name": "adhoc-1771063645",
  "feishu_target": "user:ou_xxx",
  "output": "已创建 bg_test.txt",
  "status": "done"
}
```

### 文件说明

| 文件 | 路径 | 说明 |
|------|------|------|
| task-meta.json | ~/.openclaw/data/claude-code-results/ | 任务元数据 |
| task-output.txt | ~/.openclaw/data/claude-code-results/ | Claude Code 原始输出 |
| latest.json | ~/.openclaw/data/claude-code-results/ | 完整结果 |
| pending-wake.json | ~/.openclaw/data/claude-code-results/ | 唤醒文件 |
| hook.log | ~/.openclaw/data/claude-code-results/ | Hook 日志 |

---

## 常见问题

### Q: 通知发两次怎么办？
**A**: 当前只用 SessionEnd Hook，不会重复

### Q: 通知内容为空怎么办？
**A**: 检查 hook.log 确认输出文件是否有内容

### Q: 如何调试？
**A**: 查看日志
```bash
tail -f ~/.openclaw/data/claude-code-results/hook.log
```

### Q: Hook 需要手动触发吗？
**A**: 不需要，Claude Code 会自动触发 SessionEnd

### Q: 大任务超时怎么办？
**A**: 飞书消息后台发送，没有超时限制

---

## 参考

- 原文仓库：https://github.com/win4r/claude-code-hooks
- 本仓库：https://github.com/hcgy/bot-skills-claude-code-hooks

---

## 更新日志

### 2026-02-14
- 初始化项目
- 只用 SessionEnd Hook
- 飞书消息后台发送
- 移除超时限制
