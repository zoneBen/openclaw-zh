# OpenClaw 项目分析

本文档是 OpenClaw 项目的全面技术分析，包括架构设计、核心模块、数据流和扩展开发指南。

## 项目概述

**OpenClaw** 是一个**个人 AI 助手网关系统**，核心设计理念是：
- 运行在用户自己的设备上（local-first）
- 通过多种即时通讯渠道与用户交互（WhatsApp、Telegram、Slack、Discord、Signal、iMessage 等）
- 作为"控制平面"统一管理和调度 AI 代理、工具和会话

项目名称演变：Warelay → Clawdbot → Moltbot → OpenClaw

## 核心架构设计

### 架构图（简化）

```
┌─────────────────────────────────────────────────────────────┐
│                    消息渠道层 (Channels)                      │
│  WhatsApp │ Telegram │ Slack │ Discord │ Signal │ iMessage   │
│  Google Chat │ LINE │ Matrix │ Teams │ 更多...                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Gateway (控制平面)                          │
│  ws://127.0.0.1:18789                                        │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐  │
│  │ Session Mgr │ Channel Mgr │   Auth      │   HTTP      │  │
│  │   Manager   │   Registry  │   System    │   Server    │  │
│  └─────────────┴─────────────┴─────────────┴─────────────┘  │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐  │
│  │   Control   │   Webhook   │    Cron     │   Device    │  │
│  │     UI      │   Targets   │   Scheduler │   Nodes     │  │
│  └─────────────┴─────────────┴─────────────┴─────────────┘  │
└─────────────────────────────────────────────────────────────┘
                 │                  │
        ┌────────┴────────┐         │
        ▼                 ▼         ▼
┌───────────────┐  ┌──────────────┐  ┌──────────────┐
│  Pi Agent     │  │   CLI        │  │  Companion   │
│  (RPC Mode)   │  │   Tools      │  │  Apps        │
│               │  │              │  │  (macOS/iOS/ │
│  - 工具调用   │  │  - 消息发送  │  │   Android)   │
│  - 流式响应   │  │  - 配置管理  │  │              │
│  - 会话管理   │  │  - 渠道状态  │  │  - Voice Wake│
│               │  │              │  │  - Talk Mode │
└───────────────┘  └──────────────┘  └──────────────┘
```

## 目录结构分析

```
openclaw-zh/
├── src/                          # 核心源代码
│   ├── acp/                      # Agent Client Protocol - IDE 集成桥接
│   ├── agents/                   # AI 代理核心逻辑 (60+ 文件)
│   │   ├── auth-profiles.ts      # 认证配置管理
│   │   ├── apply-patch.ts        # 代码补丁工具
│   │   ├── bash-tools.*          # Bash 执行工具
│   │   └── ...
│   ├── auto-reply/               # 自动回复系统
│   ├── browser/                  # 浏览器自动化工具
│   ├── canvas-host/              # Canvas A2UI 渲染主机
│   ├── channels/                 # 渠道通用逻辑 (50+ 文件)
│   │   ├── allow-from.ts         # 发送者白名单
│   │   ├── mention-gating.ts     # 提及门控
│   │   ├── command-gating.ts     # 命令授权
│   │   ├── session.ts            # 会话管理
│   │   └── plugins/              # 渠道插件 SDK
│   ├── cli/                      # CLI 命令框架 (100+ 文件)
│   │   ├── program.ts            # Commander 程序定义
│   │   ├── deps.ts               # 依赖注入
│   │   └── ...
│   ├── commands/                 # CLI 命令实现
│   ├── config/                   # 配置系统
│   │   ├── config.ts             # 主配置加载
│   │   ├── sessions/             # 会话存储
│   │   └── zod-schema.*          # Zod 类型定义
│   ├── discord/                  # Discord 渠道实现
│   ├── gateway/                  # Gateway 服务器核心 (70+ 文件)
│   │   ├── boot.ts               # 启动引导
│   │   ├── server.impl.ts        # 服务器实现
│   │   ├── control-ui.ts         # 控制界面
│   │   ├── hooks.ts              # Webhook 处理
│   │   └── ...
│   ├── infra/                    # 基础设施层 (100+ 文件)
│   │   ├── binaries.ts           # 二进制管理
│   │   ├── ports.ts              # 端口管理
│   │   ├── runtime-guard.ts      # 运行时检查
│   │   └── ...
│   ├── media/                    # 媒体处理管道
│   ├── media-understanding/      # 媒体理解（多模态）
│   ├── memory/                   # 记忆系统
│   ├── plugin-sdk/               # 插件 SDK 导出
│   ├── plugins/                  # 插件运行时
│   ├── routing/                  # 消息路由
│   │   ├── session-key.ts        # 会话键生成
│   │   ├── resolve-route.ts      # 路由解析
│   │   └── account-lookup.ts     # 账户查找
│   ├── security/                 # 安全模块
│   └── terminal/                 # 终端 UI 组件
│
├── extensions/                   # 扩展/插件目录 (42 个插件)
│   ├── discord/                  # Discord 扩展
│   ├── telegram/                 # Telegram 扩展
│   ├── signal/                   # Signal 扩展
│   ├── voice-call/               # 语音通话扩展
│   ├── memory-lancedb/           # LanceDB 记忆后端
│   └── ... (共 40+ 扩展)
│
├── apps/                         # 客户端应用
│   ├── macos/                    # macOS 菜单栏应用
│   ├── ios/                      # iOS 应用
│   └── android/                  # Android 应用
│
├── docs/                         # 文档 (Mintlify)
│   ├── channels/                 # 渠道文档
│   ├── gateway/                  # 网关文档
│   ├── tools/                    # 工具文档
│   └── zh-CN/                    # 中文翻译 (自动生成)
│
├── scripts/                      # 构建/测试脚本
├── skills/                       # 技能定义 (50+ 技能)
└── ui/                           # Web UI 前端
```

## 核心模块详解

### 1. Gateway 服务器 (`src/gateway/`)

Gateway 是整个系统的**控制平面**，运行在本地（默认端口 18789），提供：

| 功能 | 文件 | 说明 |
|------|------|------|
| WebSocket 服务器 | `server.impl.ts` | 处理所有客户端连接 |
| 会话管理 | `session-*` | 会话创建/恢复/重置 |
| 认证系统 | `auth.ts`, `auth-rate-limit.ts` | OAuth/API 密钥管理 |
| Webhook 处理 | `hooks.ts` | 接收渠道事件 |
| Control UI | `control-ui.ts` | Web 管理界面 |
| 设备节点 | `node-*.ts` | 连接 macOS/iOS/Android |

### 2. 渠道系统 (`src/channels/` + `extensions/`)

**设计理念**：渠道适配器模式，统一接口，独立实现

渠道插件标准接口：

```typescript
interface ChannelGatewayAdapter {
  start(): Promise<void>;
  stop(): Promise<void>;
}

interface ChannelMessagingAdapter {
  send(message: OutboundMessage): Promise<void>;
}

interface ChannelStreamingAdapter {
  // 支持流式响应
}
```

**支持的渠道**（核心 + 扩展）：
- **核心渠道**：Telegram, WhatsApp, Discord, Slack, Signal, Google Chat
- **扩展渠道**：LINE, Matrix, Teams, Feishu, Nostr, Twitch, Zalo 等 20+

### 3. Agent 系统 (`src/agents/`)

基于 **Pi Agent Runtime** (`@mariozechner/pi-*`) 构建：

| 模块 | 功能 |
|------|------|
| `auth-profiles.ts` | 多模型认证配置（支持轮换、故障转移） |
| `apply-patch.ts` | 代码补丁生成和应用 |
| `bash-tools.ts` | Shell 命令执行 |
| `acp-spawn.ts` | ACP 会话生成 |

**会话模型**：
```typescript
// 会话键格式：agent:{agentId}:{sessionId}
// 示例：agent:main:main, agent:design:feature-x
```

### 4. Plugin SDK (`src/plugin-sdk/`)

为扩展开发者提供的 SDK，包括：

- **渠道插件**：消息收发、二维码登录、状态检测
- **工具插件**：自定义工具注册
- **记忆插件**：向量数据库后端
- **认证插件**：OAuth 流程处理

### 5. ACP (Agent Client Protocol) (`src/acp/`)

与 IDE 集成的协议桥接：

```
IDE (Zed/Cursor) ←→ ACP (stdio) ←→ Gateway (WebSocket)
```

支持功能：
- 会话映射和恢复
- 流式响应转发
- 工具调用代理

## 数据流示例

### 消息处理流程

```
1. 用户发送消息 (Telegram)
   ↓
2. Telegram webhook → Gateway
   ↓
3. 路由解析 (resolve-route.ts)
   - 渠道类型识别
   - 发送者白名单检查
   - 会话键生成
   ↓
4. 会话管理
   - 加载/创建会话
   - 历史记录更新
   ↓
5. 转发到 Pi Agent (RPC)
   ↓
6. Agent 处理
   - 调用工具（浏览器、文件、Shell 等）
   - 流式响应生成
   ↓
7. 响应返回渠道
   - 分块发送
   - 媒体处理
   - 已读回执
```

## 技术栈

| 类别 | 技术选型 |
|------|----------|
| **运行时** | Node.js 22+ (ESM) |
| **语言** | TypeScript |
| **包管理** | pnpm (首选), bun (支持) |
| **构建工具** | tsdown (beta), TypeScript |
| **测试框架** | Vitest |
| **Lint/Format** | Oxlint, Oxfmt |
| **CLI 框架** | Commander |
| **WebSocket** | ws |
| **HTTP 服务器** | Express 5 |
| **数据库** | SQLite (会话存储) |
| **Agent 运行时** | @mariozechner/pi-* |

## 关键设计模式

### 1. 插件化架构
- 核心保持精简，功能通过扩展实现
- 插件 SDK 提供标准接口
- npm 分发 + 本地开发模式

### 2. 会话隔离
- 每个 Agent 独立会话存储
- 支持会话标签和恢复
- ACP 会话映射到 Gateway 会话

### 3. 安全设计
- DM 配对模式（默认阻止陌生消息）
- 发送者白名单机制
- SSRF 防护（网络请求过滤）
- 认证配置文件轮换

### 4. 流式响应
- 支持 Token 级流式输出
- 分块发送到渠道
- 打字指示器集成

## 核心命令

```bash
# 安装和启动
npm install -g openclaw
openclaw onboard --install-daemon
openclaw gateway --port 18789

# CLI 使用
openclaw message send --to +1234567890 --message "Hello"
openclaw agent --message "任务" --thinking high
openclaw channels status
openclaw config set <key> <value>

# 开发
pnpm install
pnpm build
pnpm test
pnpm gateway:watch  # 开发模式
```

## 项目特点总结

1. **Local-first 设计**：所有数据和控制都在本地
2. **多渠道统一**：一个网关管理所有消息渠道
3. **插件化扩展**：丰富的插件生态系统
4. **跨平台客户端**：macOS/iOS/Android 原生应用
5. **IDE 集成**：通过 ACP 协议支持 Zed 等编辑器
6. **安全优先**：默认安全配置，明确的风险控制

## 相关文档链接

- [Gateway 文档](https://docs.openclaw.ai/gateway)
- [渠道文档](https://docs.openclaw.ai/channels)
- [插件开发](https://docs.openclaw.ai/tools/plugin)
- [Agent 概念](https://docs.openclaw.ai/concepts/agent)
