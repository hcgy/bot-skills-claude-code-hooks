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

## Agent Teams 代理问题修复

### 问题原因

在 WSL2 环境下使用 Agent Teams 模式时，子进程（Claude Code）无法访问网络。这是因为：

1. **WSL2 网络架构**：WSL2 运行在独立的虚拟机中，通过 NAT 模式访问 Windows 主机网络
2. **代理隔离**：Windows 主机上的代理服务（如 Clash Verge）在 `127.0.0.1:4780` 监听，但 WSL2 子进程默认没有配置代理环境变量
3. **超时问题**：Claude Code 发起 API 请求时无法通过代理访问外网，导致请求超时失败

### 修复方案

在 `scripts/claude_code_run.py` 中实现了完整的代理配置：

#### 1. 动态获取 WSL2 主机 IP

```python
def get_wsl_host_ip() -> str | None:
    """Get the Windows host IP from WSL's /etc/resolv.conf."""
    try:
        result = os.popen("cat /etc/resolv.conf | grep nameserver | awk '{print $2}'").read().strip()
        if result:
            return result
    except OSError:
        pass
    return None
```

WSL2 通过 `/etc/resolv.conf` 提供 Windows 主机 IP（通常是 `172.x.x.x` 网段）。

#### 2. 自动配置代理环境变量

```python
def configure_proxy() -> None:
    """Configure HTTP/HTTPS proxy for subprocess communication."""
    # Skip if proxy already configured
    if os.environ.get("http_proxy") or os.environ.get("https_proxy"):
        return

    wsl_ip = get_wsl_host_ip()
    if wsl_ip:
        proxy_url = f"http://{wsl_ip}:4780"
        os.environ["http_proxy"] = proxy_url
        os.environ["https_proxy"] = proxy_url
        os.environ["HTTP_PROXY"] = proxy_url
        os.environ["HTTPS_PROXY"] = proxy_url
```

- 在模块加载时自动调用 `configure_proxy()`
- 优先使用已配置的代理，避免重复设置
- 同时设置小写和大写环境变量（兼容不同工具）

#### 3. 子进程代理传递

**Headless 模式**（`build_agent_teams_env` 函数）：
```python
def build_agent_teams_env(args: argparse.Namespace) -> dict[str, str]:
    """Build environment dict with Agent Teams support."""
    env = os.environ.copy()
    # ...
    # Explicitly propagate proxy settings to subprocesses
    for proxy_var in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
        if proxy_var in os.environ:
            env[proxy_var] = os.environ[proxy_var]
    return env
```

**Interactive 模式**（tmux 会话）：
```python
# Propagate proxy settings to tmux session for subprocess communication
for proxy_var in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
    proxy_val = os.environ.get(proxy_var)
    if proxy_val:
        subprocess.check_call(tmux_cmd(socket_path, "send-keys", "-t", target, "-l", "--",
            f"export {proxy_var}={shlex.quote(proxy_val)}"))
```

### 代理配置方式

| 场景 | 代理地址 | 说明 |
|------|----------|------|
| WSL2 自动 | `http://<WSL主机IP>:4780` | 通过 `/etc/resolv.conf` 动态获取 |
| 手动配置 | 用户自定义 | 如果环境变量已有代理设置，则跳过自动配置 |

### 关键文件

- **入口脚本**：`scripts/claude_code_run.py`
- **代理配置函数**：
  - `get_wsl_host_ip()` - 获取 WSL2 主机 IP
  - `configure_proxy()` - 配置代理环境变量
  - `build_agent_teams_env()` - 构建带代理的环境变量

### 相关参数

| 参数 | 说明 |
|------|------|
| `--agent-teams` | 启用 Agent Teams 模式 |
| `--teammate-mode` | 指定子代理模式：`auto`、`in-process`、`tmux` |

## 派发任务最佳实践

由于 Claude Code 每次都是全新会话，只有我这边有记忆。所以派发任务时要：

### 🎯 角色分工

| 角色 | 职责 |
|------|------|
| **我 (OpenClaw)** | 理解需求、准备上下文、派发任务、汇报结果 |
| **Claude Code** | 执行开发任务（检查+修改+测试） |

### ✅ 派发流程

1. **理解任务** - 明确用户要什么
2. **准备上下文** - 提供足够的项目信息
3. **派发** - 用 skill 派给 Claude Code
4. **等待通知** - 用户通过飞书收到完成通知
5. **汇报** - 读取结果，告诉用户

### ✅ 必须提供的上下文

1. **项目背景** - 项目的目的是什么
2. **技术栈** - 用什么语言/框架
3. **关键文件** - 哪些文件可能需要修改
4. **约束条件** - 有什么限制（如不浪费 token）
5. **工作目录** - --workdir 参数

### ⚠️ 派发原则

1. **派完整的任务** - 让 Claude Code 直接完成，不要只检查不修改
2. **不要给太多上下文** - 只给关键信息，避免浪费 token
3. **每次都是全新会话** - 重要信息要重复
4. **明确任务范围** - 太大或太小都不好

### 📝 派发模板

```
/claude-code-dispatch -f "user:ou_xxx" \
  -p "任务描述

项目信息：
- 目录：/path/to/project
- 技术栈：xxx
- 关键文件：xxx

要求：
1. xxx
2. xxx

约束：不要浪费 token" \
  --workdir "/path/to/project"
```
