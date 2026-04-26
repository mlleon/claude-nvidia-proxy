# Claude Code + NVIDIA Hosted API 代理使用清单

本文档整理了在 Ubuntu / WSL 环境中使用 `claude-nvidia-proxy` 的推荐方式。

适用目标：
- 使用官方 Claude Code
- 底层模型走 NVIDIA hosted API：`https://integrate.api.nvidia.com/v1`
- 通过本地代理把 Anthropic `/v1/messages` 转成 NVIDIA `/v1/chat/completions`
- 默认仍可继续使用官方 Claude API，只有在你显式设置环境变量时才走本地代理

推荐主线：
- 使用 `config.json` 保存 `nvidia_url` 和 `nvidia_key`
- 使用根目录 `start.sh` 启动代理
- 推荐监听端口使用 `8082`
- 在 WSL / Ubuntu 中优先使用 **systemd 用户服务** 管理代理
- Claude Code 默认不改环境变量；需要走代理时再临时 `export`

---

## 1. 前置说明

这个项目有两层“默认值”，需要先区分清楚：

### 程序默认值
程序本身在 `main.go` 中默认监听：

```text
:3001
```

### 当前推荐运行方式
本仓库根目录的 `start.sh` 会在启动前设置：

```bash
export ADDR=":8082"
```

所以如果你是通过本文档的主线方式运行：
- 实际监听端口是 `8082`
- 相关验证命令、`curl` 示例、Claude 代理地址都应写成 `http://127.0.0.1:8082`

---

## 2. 安装 Go

该仓库要求 Go 1.22+。

### 推荐安装方式

```bash
sudo snap install go --classic
```

### 验证版本

```bash
go version
```

预期输出类似：

```bash
go version go1.26.2 linux/amd64
```

只要版本大于等于 1.22 即可。

---

## 3. 获取项目并进入目录

```bash
cd ~/claude-nvidia-proxy
```

如果仓库还没拉下来：

```bash
git clone https://github.com/zhangrr/claude-nvidia-proxy.git
cd claude-nvidia-proxy
```

---

## 4. 配置 `config.json`

编辑根目录 `config.json`：

```json
{
  "nvidia_url": "https://integrate.api.nvidia.com/v1/chat/completions",
  "nvidia_key": "你的NVIDIA_API_KEY"
}
```

说明：
- `nvidia_url`：NVIDIA hosted API 上游地址
- `nvidia_key`：你的 NVIDIA API Key
- 不要把真实 key 提交到 Git

### 配置优先级

程序读取配置时，优先级如下：
1. 环境变量覆盖
2. `config.json`

常见可覆盖项：
- `UPSTREAM_URL`：覆盖 `nvidia_url`
- `PROVIDER_API_KEY`：覆盖 `nvidia_key`
- `SERVER_API_KEY`：为代理入口开启鉴权
- `ADDR`：覆盖监听端口

如果你按本文档主线操作，通常只需要维护 `config.json`，不需要额外设置 `PROVIDER_API_KEY` 或 `UPSTREAM_URL`。

---

## 5. 检查并准备 `start.sh`

当前推荐的 `start.sh` 内容如下：

```bash
#!/usr/bin/env bash
set -euo pipefail
export ADDR=":8082"
export LOG_BODY_MAX_CHARS=0
export LOG_STREAM_TEXT_PREVIEW_CHARS=0
if [ ! -f ./claude-nvidia-proxy ]; then
  go build -o claude-nvidia-proxy .
fi
exec ./claude-nvidia-proxy
```

说明：
- 监听端口通过 `ADDR` 控制，这里固定为 `8082`
- 日志 body 和流式预览都被关闭，避免输出过多内容
- 如果根目录还没有编译好的二进制，脚本会先执行一次 `go build`
- 上游地址和上游密钥仍然来自 `config.json`

给脚本执行权限：

```bash
chmod +x ~/claude-nvidia-proxy/start.sh
```

---

## 6. 推荐方式：使用 systemd 用户服务自动启动

如果你在 Ubuntu / WSL 中长期使用这个代理，推荐把它交给 systemd 用户服务管理。

这样做的好处：
- 登录后自动启动
- 进程崩溃后可自动重启
- 不需要每次手动 `nohup`
- 日志统一通过 `journalctl` 查看

### 6.1 创建服务文件

创建目录：

```bash
mkdir -p ~/.config/systemd/user
```

创建文件：

```bash
nano ~/.config/systemd/user/claude-nvidia-proxy.service
```

填入以下内容：

```ini
[Unit]
Description=Claude NVIDIA Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/你的用户名/claude-nvidia-proxy
ExecStart=/home/你的用户名/claude-nvidia-proxy/start.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

如果你的用户名是 `mleon`，则实际路径应为：

```ini
WorkingDirectory=/home/mleon/claude-nvidia-proxy
ExecStart=/home/mleon/claude-nvidia-proxy/start.sh
```

### 6.2 重新加载并启用服务

```bash
systemctl --user daemon-reload
systemctl --user enable claude-nvidia-proxy
systemctl --user start claude-nvidia-proxy
```

说明：
- `daemon-reload`：重新加载用户服务配置
- `enable`：设置登录后自动启动，只需执行一次
- `start`：立刻启动当前服务

### 6.3 查看服务状态

```bash
systemctl --user status claude-nvidia-proxy
```

正常情况下应看到类似：

```text
Loaded: loaded (.../claude-nvidia-proxy.service; enabled; ...)
Active: active (running)
```

### 6.4 查看服务日志

```bash
journalctl --user -u claude-nvidia-proxy -f
```

正常日志类似：

```text
listening on :8082
upstream: https://integrate.api.nvidia.com/v1/chat/completions
inbound auth: disabled (SERVER_API_KEY not set)
```

### 6.5 常用管理命令

```bash
systemctl --user restart claude-nvidia-proxy
systemctl --user stop claude-nvidia-proxy
systemctl --user status claude-nvidia-proxy
journalctl --user -u claude-nvidia-proxy -f
```

---

## 7. 备选方式：前台启动或 `nohup` 后台启动

如果你暂时不想配置 systemd，也可以继续手动启动。

### 前台启动

```bash
cd ~/claude-nvidia-proxy
./start.sh
```

启动成功后，终端应看到类似：

```text
listening on :8082
upstream: https://integrate.api.nvidia.com/v1/chat/completions
inbound auth: disabled (SERVER_API_KEY not set)
```

### `nohup` 后台启动

```bash
cd ~/claude-nvidia-proxy
nohup ./start.sh > proxy.log 2>&1 &
```

说明：
- 进程会在后台运行
- 日志写入当前目录 `proxy.log`
- 关闭终端后进程不会退出
- 如果你已经切换到 systemd 管理，就不要再重复用 `nohup` 启动同一个端口

### 查看日志

```bash
tail -f ~/claude-nvidia-proxy/proxy.log
```

### 检查是否监听成功

```bash
ss -ltnp | grep 8082
```

### 停止手动启动的后台进程

先看端口监听：

```bash
ss -ltnp | grep 8082
```

如果看到 PID，再停止：

```bash
kill 真实PID
```

如果普通 `kill` 后还不退出，再使用：

```bash
kill -9 真实PID
```

---

## 8. 验证代理是否可用

在新终端执行：

```bash
curl -sS http://127.0.0.1:8082/v1/messages \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"z-ai/glm4.7",
    "max_tokens":128,
    "messages":[{"role":"user","content":"只回复 OK"}]
  }'
```

如果返回正常 JSON，说明代理已经把 Anthropic 风格请求成功转发给 NVIDIA。

---

## 9. Claude Code 如何与代理配合

### 推荐原则

如果你希望：
- 代理常驻运行
- Claude Code 默认仍走官方 API
- 只有在需要时才临时走 NVIDIA 代理

那么**不要**把 `ANTHROPIC_BASE_URL` 一类变量写进 `~/.bashrc`、`~/.zshrc` 或 systemd 服务里。

### 默认情况

直接运行：

```bash
claude
```

此时 Claude Code 仍然走官方 API，和本地代理没有关系。

### 仅在当前终端临时走代理

在当前终端执行：

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:8082"
export ANTHROPIC_AUTH_TOKEN="dummy"
```

然后再运行：

```bash
claude
```

说明：
- `ANTHROPIC_BASE_URL` 必须和代理监听端口一致
- `ANTHROPIC_AUTH_TOKEN` 在未启用 `SERVER_API_KEY` 时可用任意占位值，例如 `dummy`
- 真实 NVIDIA key 应只保存在代理侧 `config.json` 中，不要直接给 Claude Code

### 如果你想临时指定模型

你可以在当前终端继续设置：

```bash
export ANTHROPIC_DEFAULT_HAIKU_MODEL="z-ai/glm4.7"
export ANTHROPIC_DEFAULT_SONNET_MODEL="z-ai/glm4.7"
export ANTHROPIC_DEFAULT_OPUS_MODEL="z-ai/glm4.7"
```

或者改成你需要的 NVIDIA 模型，例如：
- `z-ai/glm4.7`
- `z-ai/glm5`
- `moonshotai/kimi-k2.5`
- `minimaxai/minimax-m2.1`

如果你不设置这些变量，Claude Code 的默认模型行为仍取决于你当前的官方配置。

---

## 10. 如果要切换模型

只要目标模型是 NVIDIA Hosted API 支持的模型，就可以在请求里透传。

临时切换时，建议把以下变量一起改成同一个模型名：
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`
- `ANTHROPIC_DEFAULT_OPUS_MODEL`

例如换成 `moonshotai/kimi-k2.5`：

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:8082"
export ANTHROPIC_AUTH_TOKEN="dummy"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="moonshotai/kimi-k2.5"
export ANTHROPIC_DEFAULT_SONNET_MODEL="moonshotai/kimi-k2.5"
export ANTHROPIC_DEFAULT_OPUS_MODEL="moonshotai/kimi-k2.5"

claude
```

如果你没有设置 `ANTHROPIC_BASE_URL`，那这些模型设置不会把请求自动切到本地代理。

---

## 11. 常见问题

### `go: command not found`
说明系统还没装 Go。

先执行：

```bash
sudo snap install go --classic
```

---

### 改端口什么时候生效？
必须在启动前设置，例如修改 `start.sh` 里的：

```bash
export ADDR=":8082"
```

程序启动后再改不会生效，必须重启代理。

如果你使用的是 systemd 用户服务，改完后要重启服务：

```bash
systemctl --user restart claude-nvidia-proxy
```

---

### `missing nvidia_key in config.json (or PROVIDER_API_KEY)`
没有设置 NVIDIA API Key。

检查：
- `config.json` 中是否有 `nvidia_key`
- 或是否设置了 `PROVIDER_API_KEY`

如果你按本文档主线操作，优先检查 `config.json`。

---

### `missing nvidia_url in config.json (or UPSTREAM_URL)`
没有设置上游地址。

检查：
- `config.json` 中是否有 `nvidia_url`
- 或是否设置了 `UPSTREAM_URL`

如果你按本文档主线操作，优先检查 `config.json`。

---

### `unauthorized`
通常是启用了代理入口鉴权 `SERVER_API_KEY`，但请求没带对 key。

如果你没有这个需求，不要设置 `SERVER_API_KEY`。

如果你启用了它，请在请求中带上：
- `Authorization: Bearer 你的SERVER_API_KEY`
- 或 `x-api-key: 你的SERVER_API_KEY`

---

### 为什么 `kill` 之后还能看到 `grep claude-nvidia-proxy`？
这通常不是代理还活着，而是你自己刚运行的 `grep` 命令被显示出来了。

例如你执行：

```bash
ps -ef | grep claude-nvidia-proxy
```

输出里如果是这种：

```bash
grep --color=auto claude-nvidia-proxy
```

说明这行只是 `grep` 自己，不是代理进程。

更准确的查看方式：

```bash
ps -ef | grep '[c]laude-nvidia-proxy'
```

或者：

```bash
ps -ef | grep claude-nvidia-proxy | grep -v grep
```

更推荐直接按端口检查：

```bash
ss -ltnp | grep 8082
```

如果没有输出，说明代理已经停止。

---

### `kill PID` 报错 `arguments must be process or job IDs`
说明你把 `PID` 当成字面量输进去了。

错误示例：

```bash
kill PID
```

正确示例：

```bash
kill 473105
```

---

### `kill 某个数字` 后提示 `No such process`
通常说明你杀的是刚刚那条 `grep` 进程，而 `grep` 在命令结束后已经退出了。

这种情况下，优先用下面的方法确认真正的代理进程：

```bash
ss -ltnp | grep 8082
```

或者：

```bash
ps -ef | grep '[c]laude-nvidia-proxy'
```

---

### Claude Code 连不上代理
重点检查：
- 代理是否已经启动
- `ANTHROPIC_BASE_URL` 是否是 `http://127.0.0.1:8082`
- 本地 `curl` 是否能成功请求 `/v1/messages`
- 如果代理由 systemd 管理，先看：

```bash
systemctl --user status claude-nvidia-proxy
journalctl --user -u claude-nvidia-proxy -n 50 --no-pager
```

---

### 代理已经运行，但我仍想继续使用官方 Claude API，会有影响吗？
没有影响。

代理只是本地监听的一个服务：
- 只要你没有显式设置 `ANTHROPIC_BASE_URL=http://127.0.0.1:8082`
- Claude Code 就不会主动走这个代理

也就是说：
- 代理可以长期运行
- Claude 默认仍然可以继续用官方 API
- 只有你在当前终端显式导出代理环境变量时，Claude 才会改走本地代理
