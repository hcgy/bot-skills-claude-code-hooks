# 🤖 Bot Skills - Claude Code 自动化开发方案

> 基于 OpenClaw + Claude Code 的零轮询开发方案，让 AI 帮你写代码

## 🎯 核心思想

**派发后不管，完成自动通知**

```
用户 → OpenClaw → dispatch → Claude Code (后台运行) → Hook → 飞书通知 → 用户
```

### 为什么这样做？

| 传统方式 | 我们的方式 |
|---------|-----------|
| OpenClaw 轮询检查状态 | Claude Code 完成后自动回调 |
| 每次轮询消耗 tokens | 不消耗额外 tokens |
| 等待时间长 | 后台并行运行 |

---

## 📁 项目结构

```
bot-skills/
├── README.md                        # 项目说明
├── claude-code-hooks/              # Claude Code Hook 脚本
│   ├── notify-agi.sh              # 核心回调脚本
│   └── dispatch.sh                 # 任务派发脚本
├── openclaw-skills/                # OpenClaw Skills
│   └── claude-code-dispatch/      # dispatch skill
└── configs/                        # 配置示例
    └── settings.json               # Claude Code 配置
```

---

## 🚀 快速开始

### 环境要求

1. **OpenClaw** - 已安装并配置飞书
2. **Claude Code** - 已配置 API
3. **Git** - 已安装

### 安装步骤

#### 1. 克隆项目

```bash
git clone https://github.com/你的用户名/bot-skills.git
cd bot-skills
```

#### 2. 配置 Claude Code Hook

```bash
# 复制 Hook 脚本
cp claude-code-hooks/notify-agi.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/notify-agi.sh

# 配置 Claude Code（添加到 settings.json）
# 见 configs/settings.json 示例
```

#### 3. 配置 OpenClaw Skill

```bash
cp -r openclaw-skills/claude-code-dispatch ~/.openclaw/skills/
openclaw gateway restart
```

#### 4. 开始使用

```bash
# 派发任务到 Claude Code
/claude-code-dispatch -f "user:飞书用户ID" -p "写一个 Python 计算器" --workdir "/项目路径"
```

---

## 📖 工作原理

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
   自动触发 Hook
       ↓
   ┌── Stop Hook ──┐
   ↓               ↓
尝试发送       尝试发送
(可能失败)     (通常成功)
       ↓
   飞书通知 → 用户收到
```

### 3. 为什么需要两个 Hook？

Claude Code 有两个生命周期点：

| Hook 名称 | 触发时机 | 说明 |
|-----------|---------|------|
| **Stop** | 生成停止时 | 可能输出未完成 |
| **SessionEnd** | 会话结束时 | 输出完整 |

**双通道保障**：第一次可能失败（输出未写完），第二次确保成功。

### 4. 防重复机制

原始代码有锁文件机制：

```bash
LOCK_FILE="${RESULT_DIR}/.hook-lock"
LOCK_AGE_LIMIT=30  # 30秒内重复触发视为同一任务

if [ -f "$LOCK_FILE" ]; then
    LOCK_TIME=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$(( NOW - LOCK_TIME ))
    if [ "$AGE" -lt "$LOCK_AGE_LIMIT" ]; then
        exit 0  # 跳过
    fi
fi
```

---

## ⚙️ 配置说明

### dispatch 参数

| 参数 | 简写 | 说明 | 必需 |
|------|------|------|------|
| --feishu | -f | 飞书用户 ID | ✅ |
| --prompt | -p | 任务描述 | ✅ |
| --workdir | -w | 工作目录 | 可选 |
| --permission-mode | - | 权限模式 | 可选 |
| --agent-teams | - | 启用 Agent Teams | 可选 |

### 示例

```bash
# 简单任务
/claude-code-dispatch -f "user:ou_xxx" -p "写一个 Hello World"

# 复杂任务
/claude-code-dispatch -f "user:ou_xxx" -p "用 Flask 写一个 REST API" --workdir "/home/user/project"

# Agent Teams 模式
/claude-code-dispatch -f "user:ou_xxx" --agent-teams -p "重构整个前端项目"
```

---

## 🔧 核心文件

### notify-agi.sh

这是 Hook 回调脚本，负责：
1. 读取 Claude Code 的输出
2. 写入 latest.json 结果文件
3. 发送飞书通知
4. 唤醒 OpenClaw 会话

### dispatch.sh

任务派发脚本，负责：
1. 写入任务元数据
2. 启动 Claude Code
3. 捕获输出

---

## ❓ 常见问题

### Q: 通知发两次怎么办？
**A**: 检查锁文件是否生效，当前脚本已有去重逻辑

### Q: 通知内容为空怎么办？
**A**: Stop Hook 可能在输出写完前触发，SessionEnd 会重试

### Q: 如何调试？
**A**: 查看日志
```bash
tail -f ~/.openclaw/data/claude-code-results/hook.log
```

### Q: Hook 需要手动触发吗？
**A**: 不需要，Claude Code 会自动触发

---

## 📚 参考资料

- 原文文章：https://www.aivi.fyi/aiagents/OpenClaw-Agent-Teams
- GitHub 原始项目：https://github.com/win4r/claude-code-hooks

---

## 📝 更新日志

### 2026-02-14
- 初始化项目
- 添加中文文档
- 包含 Hook 脚本和 dispatch 脚本

---

## License

MIT License
