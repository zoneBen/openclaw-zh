# OpenClaw 部署指南

## 部署到另一台电脑

### 方法一：使用 npm 安装（推荐）

如果目标电脑可以访问 npm：

```bash
# 1. 安装 Node.js 22+
node --version  # 确保 >= 22.12.0

# 2. 安装 OpenClaw
npm install -g openclaw@latest

# 3. 初始化配置
openclaw onboard --install-daemon

# 4. 启动网关
openclaw gateway --port 18789
```

### 方法二：复制构建文件

如果目标电脑无法访问外网，可以复制以下文件：

#### 需要复制的文件

```
openclaw-deploy/
├── dist/                    # 编译后的主程序 (约 65MB)
├── ui/dist/control-ui/      # Web 界面 (约 5MB)
├── package.json             # 项目配置
├── openclaw.mjs             # CLI 入口
└── node_modules/            # 依赖 (约 1.6GB，可选)
```

#### 打包命令

```bash
# 在当前电脑打包
cd /home/mrcong/works/openclaw-zh

# 创建部署包
mkdir -p /tmp/openclaw-deploy
cp -r dist /tmp/openclaw-deploy/
cp -r ui/dist/control-ui /tmp/openclaw-deploy/dist/
cp package.json /tmp/openclaw-deploy/
cp openclaw.mjs /tmp/openclaw-deploy/

# 压缩
cd /tmp
tar -czf openclaw-deploy.tar.gz openclaw-deploy/

# 复制到目标电脑
scp openclaw-deploy.tar.gz user@target-host:/opt/
```

#### 目标电脑配置

```bash
# 1. 解压
cd /opt
tar -xzf openclaw-deploy.tar.gz

# 2. 安装 Node.js 22+ (如果未安装)
# Ubuntu/Debian:
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# 3. 安装依赖 (如果有 node_modules 可跳过)
cd /opt/openclaw-deploy
npm install --omit=dev

# 4. 创建配置目录
mkdir -p ~/.openclaw

# 5. 初始化配置
node openclaw.mjs onboard --install-daemon

# 6. 启动网关
node openclaw.mjs gateway --port 18789

# 或使用 menubar app
nohup node openclaw.mjs gateway --port 18789 > /tmp/openclaw-gateway.log 2>&1 &
```

### 方法三：使用 Docker

```bash
# 在目标电脑运行 Docker 版本
docker run -d \
  --name openclaw \
  -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  openclaw/openclaw:latest
```

## 访问 Dashboard

启动后，在浏览器访问：

```
http://localhost:18789/control-ui/
```

如果启用了认证，需要添加 token：

```
http://localhost:18789/control-ui/?token=YOUR_TOKEN
```

## 配置中文界面

Dashboard 默认使用简体中文。如果需要切换语言：

1. 点击右上角设置
2. 选择 Language → English/简体中文

## 配置文件位置

```
~/.openclaw/
├── openclaw.json          # 主配置文件
├── credentials/           # 认证凭据
├── sessions/              # 会话数据
└── agents/                # Agent 数据
```

## 常用命令

```bash
# 查看状态
openclaw channels status

# 发送消息
openclaw message send --to <recipient> --message "Hello"

# 查看日志
openclaw logs tail

# 配置修改
openclaw config set <key> <value>

# 重启网关
pkill -9 -f openclaw-gateway
openclaw gateway --port 18789 &
```

## 生产环境部署

### systemd 服务 (Linux)

创建 `/etc/systemd/system/openclaw.service`：

```ini
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/opt/openclaw-deploy
ExecStart=/usr/bin/node openclaw.mjs gateway --port 18789
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启动服务：

```bash
systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw
systemctl status openclaw
```

### launchd 服务 (macOS)

创建 `~/Library/LaunchAgents/ai.openclaw.gateway.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.gateway</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>/opt/openclaw-deploy/openclaw.mjs</string>
        <string>gateway</string>
        <string>--port</string>
        <string>18789</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

加载服务：

```bash
launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```
