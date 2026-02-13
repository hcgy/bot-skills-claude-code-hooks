# 🤖 Bot Skills - Claude Code Hooks 自动化开发方案

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

## 目录结构

```
bot-skills/
├── README.md                    # 本文档
├── claude-code-hooks/          # Hook 脚本
│   ├── notify-agi.sh          # 核心 Hook 脚本
│   └── dispatch.sh             # 派发脚本
├── openclaw-skills/            # OpenClaw Skills
│   └── claude-code-dispatch/  # dispatch skill
└── configs/                    # 配置文件示例
    └── settings.json           # Claude Code 配置
```

---

## 功能特性

### 1. 任务派发 (dispatch)
- 一条指令派发任务给 Claude Code
- 支持自定义工作目录
- 支持 Feishu 通知

### 2. 自动通知
- 任务完成后自动推送飞书
- 支持去重（Stop + SessionEnd 双通道）
- 自动过滤终端控制字符

### 3. 零轮询
- 不需要定时检查任务状态
- Hook 回调机制自动触发

---

## 快速开始

### 前置要求

1. **OpenClaw** 已安装
2. **Claude Code** 已配置 MiniMax API
3. **飞书机器人** 已配置

### 步骤 1：配置 Claude Code

```json
// ~/.claude/settings.json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/notify-agi.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command", 
            "command": "/path/to/notify-agi.sh",
            "timeout": 10
          }
        ]
      }
    ]
  },
  "noVerify": true,
  "skipConfirmations": true
}
```

### 步骤 2：配置 Hook 脚本

```bash
# 克隆仓库后
cp -r claude-code-hooks ~/.claude/hooks/
chmod +x ~/.claude/hooks/notify-agi.sh
```

### 步骤 3：配置 OpenClaw Skill

```bash
cp -r openclaw-skills/claude-code-dispatch ~/.openclaw/skills/
openclaw gateway restart
```

### 步骤 4：使用

```bash
# 派发任务
/claude-code-dispatch -f "user:ou_xxx" -p "写一个计算器" --workdir "/path/to/project"
```

---

## 原理详解

### 为什么需要两个 Hook？

Claude Code 有两个生命周期点：

| Hook | 触发时机 | 说明 |
|------|---------|------|
| Stop | 生成停止时 | 可能输出未完成 |
| SessionEnd | 会话结束时 | 输出完整 |

**双通道设计**：
- 第一次可能失败（输出未写完）
- 第二次确保成功
- 用锁文件避免重复处理

### 文件+信号双通道

| 通道 | 作用 |
|------|------|
| latest.json | 存储完整结果 |
| wake event | 通知 OpenClaw 读取 |

---

## 配置说明

### dispatch 参数

| 参数 | 说明 | 必需 |
|------|------|------|
| -f | Feishu 用户 ID | ✅ |
| -p | 任务描述 | ✅ |
| --workdir | 工作目录 | 可选 |
| --permission-mode | 权限模式 | 默认 bypassPermissions |

### 环境变量

```bash
OPENCLAW_GATEWAY_TOKEN=xxx    # OpenClaw 网关 token
OPENCLAW_Gateway=xxx          # OpenClaw 网关地址
```

---

## 常见问题

### Q: 通知发两次怎么办？
A: 脚本已有去重逻辑，检查锁文件是否生效

### Q: 通知为空怎么办？
A: 检查 Stop Hook 是否在输出写完前触发，SessionEnd 会重试

### Q: 如何调试？
A: 查看日志：`tail -f ~/.openclaw/data/claude-code-results/hook.log`

---

## 参考

- 原文文章：https://www.aivi.fyi/aiagents/OpenClaw-Agent-Teams
- GitHub：https://github.com/win4r/claude-code-hooks

---

## License

MIT
