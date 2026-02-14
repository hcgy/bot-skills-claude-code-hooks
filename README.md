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
├── dispatch.sh                    # 任务派发脚本（入口）
├── claude-code-hooks/
│   ├── notify-agi.sh              # SessionEnd Hook 脚本
│   └── dispatch.sh                # 任务派发脚本（旧版）
└── scripts/
    ├── claude_code_run.py          # Claude Code PTY 运行器
    └── run-claude-code.sh          # 启动脚本
```

> **说明**：派发脚本和 Hook 已合并到同一个仓库，方便统一管理和部署。

---

## 常见问题与解决方案

### 1. Agent Teams 子进程代理问题

#### 问题描述

当启用 Agent Teams（`--agent-teams`）时，Claude Code 会启动子进程（sub-agent）来处理任务。但子进程默认**不会继承父进程的环境变量**，导致子进程无法访问代理，无法访问 Anthropic API。

#### 症状

```
Error: Could not connect to API
或者
API request failed: connection refused
```

#### 解决方案

在 `dispatch.sh` 中，代理环境变量会通过 `export` 设置，确保所有子进程都能继承：

```bash
# 设置代理（WSL2 环境）
WSL_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
export http_proxy="http://${WSL_IP}:4780"
export https_proxy="http://${WSL_IP}:4780"

# 关键：设置 no_proxy 排除本地和国内服务
export no_proxy="localhost,127.0.0.1,feishu.cn,open.feishu.cn"
```

> **注意**：`export` 确保代理对所有子进程可见，包括 Agent Teams 启动的子代理。

---

### 2. Git 全局代理配置

#### 问题描述

Claude Code 在执行任务时，可能会执行 `git push`、`git pull` 等操作。如果使用了代理，这些操作也需要代理支持。

#### 解决方案

`dispatch.sh` 在启动时会自动配置 git 全局代理：

```bash
# 自动设置 git 全局代理
GIT_PROXY="http://${WSL_IP}:4780"
git config --global http.proxy "$GIT_PROXY"
git config --global https.proxy "$GIT_PROXY"

# 对国内仓库不使用代理
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
```

> **注意**：此配置在每次派发任务时自动执行，确保 git 操作使用正确的代理。

---

### 3. 任务完成后自动 Git Push

#### 功能说明

Claude Code 完成任务后，可以自动将修改推送到远程仓库。需要满足以下条件：
1. 任务元数据中包含 `auto_push: true`
2. 工作目录是 git 仓库
3. 有远程仓库配置

#### 配置方式

在派发任务时添加 `--auto-push` 参数：

```bash
/claude-code-dispatch -f "user:ou_xxx" -p "重构项目" -w "/path/to/repo" --auto-push
```

#### 实现原理

1. 任务完成后，Hook（`notify-agi.sh`）读取元数据
2. 如果 `auto_push` 为 `true`，执行自动推送
3. 推送结果通过飞书通知用户

```bash
# notify-agi.sh 中的自动推送逻辑
if [ "$AUTO_PUSH" = "true" ] && [ -d "$CWD/.git" ]; then
    (
        cd "$CWD"
        git add -A
        git commit -m "Auto commit by Claude Code: $TASK_NAME" 2>/dev/null || true
        git push origin HEAD 2>&1
    ) >> "$LOG" 2>&1 &
fi
```

#### 推送失败处理

- 如果没有需要提交的内容（nothing to commit），跳过推送
- 如果推送失败，会在飞书通知中显示错误信息

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

**重要：使用 skill 方式调用（后台执行，不阻塞）：**

```bash
# 派发任务（后台执行，立即返回）
/claude-code-dispatch -f "user:飞书用户ID" -p "写一个 Python 计算器" --workdir "/项目路径"

# 派发 Team 任务
/claude-code-dispatch -f "user:ou_xxx" -p "用 Team 方案重构项目" --workdir "/path"
```

**注意**：不要直接调用 `dispatch.sh`，要用 skill 方式 `/claude-code-dispatch`，这样才会后台执行不阻塞。

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
| --auto-push | - | 任务完成后自动 git push | 可选 |

### 示例

```bash
# 简单任务
/claude-code-dispatch -f "user:ou_xxx" -p "写一个 Hello World"

# 指定工作目录
/claude-code-dispatch -f "user:ou_xxx" -p "写一个 Flask API" -w "/home/user/project"

# Agent Teams 模式（复杂任务）
/claude-code-dispatch -f "user:ou_xxx" --agent-teams -p "重构整个前端项目"

# 自动推送模式（完成后自动 git push）
/claude-code-dispatch -f "user:ou_xxx" -p "重构项目" -w "/path/to/repo" --auto-push
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

### 2026-02-15
- 添加 Agent Teams 子进程代理配置
- 添加 git 全局代理自动配置
- 添加项目结构统一说明
- 添加任务完成后自动 git push 功能

### 2026-02-14
- 初始化项目
- 只用 SessionEnd Hook
- 飞书消息后台发送
- 移除超时限制

### 2026-02-15 (Test)
- Test push at Sun Feb 15 06:48:04 CST 2026
