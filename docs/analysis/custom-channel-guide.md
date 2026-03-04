# 自定义通道 (Channel) 实现指南

本文档详细说明如何为 OpenClaw 实现自定义消息通道，让你能够通过新的 messaging platform 控制 OpenClaw。

## 概述

OpenClaw 的通道系统采用**插件化架构**，每个通道是一个独立的插件模块，通过统一的接口与 Gateway 交互。

### 通道类型

OpenClaw 支持两种通道实现方式：

1. **核心通道** (`src/channels/<name>/`) - 内置通道，直接导入核心模块
2. **扩展通道** (`extensions/<name>/`) - 独立插件，通过 Plugin SDK 交互

**推荐从扩展通道开始**，因为：
- 独立开发，不影响核心代码
- 可以单独发布到 npm
- 使用官方 Plugin SDK API

## 通道接口详解

### 核心接口类型

通道插件需要实现 `ChannelPlugin` 接口，包含以下核心适配器：

```typescript
export type ChannelPlugin = {
  // 基本信息
  id: ChannelId;                    // 通道唯一标识
  meta: ChannelMeta;                // 元数据（名称、文档等）
  capabilities: ChannelCapabilities; // 能力声明

  // 配置相关
  config: ChannelConfigAdapter;     // 配置读取/解析
  configSchema?: ChannelConfigSchema; // 配置 Schema
  setup?: ChannelSetupAdapter;      // 安装设置逻辑

  // 消息处理
  messaging?: ChannelMessagingAdapter;  // 核心消息处理
  outbound?: ChannelOutboundAdapter;    // 消息发送
  streaming?: ChannelStreamingAdapter;  // 流式响应

  // 安全与权限
  security?: ChannelSecurityAdapter;    // DM 策略、白名单
  pairing?: ChannelPairingAdapter;      // 设备配对

  // 高级功能
  groups?: ChannelGroupAdapter;         // 群组处理
  mentions?: ChannelMentionAdapter;     // 提及处理
  threading?: ChannelThreadingAdapter;  // 线程/话题
  actions?: ChannelMessageActionAdapter; // 消息操作（回复、编辑等）

  // 状态与监控
  status?: ChannelStatusAdapter;        // 状态检测
  gateway?: ChannelGatewayAdapter;      // Gateway 生命周期
  heartbeat?: ChannelHeartbeatAdapter;  // 心跳检测
};
```

### 关键适配器说明

#### 1. ChannelConfigAdapter - 配置管理

```typescript
export type ChannelConfigAdapter<ResolvedAccount> = {
  // 列出所有账户 ID
  listAccountIds: (cfg: OpenClawConfig) => string[];

  // 解析账户配置
  resolveAccount: (cfg: OpenClawConfig, accountId?: string) => ResolvedAccount;

  // 默认账户 ID（可选）
  defaultAccountId?: (cfg: OpenClawConfig) => string;

  // 启用/禁用账户
  setAccountEnabled?: (params: { cfg, accountId, enabled }) => OpenClawConfig;

  // 检查是否已配置
  isConfigured?: (account, cfg) => boolean;
};
```

#### 2. ChannelMessagingAdapter - 消息处理

```typescript
export type ChannelMessagingAdapter = {
  // 启动消息监听
  startListening: (ctx: ChannelGatewayContext) => Promise<void>;

  // 停止监听
  stopListening: (ctx: ChannelGatewayContext) => Promise<void>;

  // 构建消息上下文（将原始消息转为统一格式）
  buildMessageContext: (rawMessage: unknown) => Promise<MessageContext>;
};
```

#### 3. ChannelOutboundAdapter - 消息发送

```typescript
export type ChannelOutboundAdapter = {
  // 发送模式：direct(直接)/gateway(通过网关)/hybrid(混合)
  deliveryMode: "direct" | "gateway" | "hybrid";

  // 发送文本消息
  sendText?: (ctx: ChannelOutboundContext) => Promise<OutboundDeliveryResult>;

  // 发送媒体消息
  sendMedia?: (ctx: ChannelOutboundContext) => Promise<OutboundDeliveryResult>;

  // 发送投票
  sendPoll?: (ctx: ChannelPollContext) => Promise<ChannelPollResult>;
};
```

#### 4. ChannelSecurityAdapter - 安全控制

```typescript
export type ChannelSecurityAdapter = {
  // 获取 DM 策略
  resolveDmPolicy: (ctx: ChannelSecurityContext) => ChannelSecurityDmPolicy;

  // 检查发送者权限
  checkSenderAccess: (params: {
    senderId: string;
    cfg: OpenClawConfig;
    accountId: string;
  }) => boolean;
};
```

## 实现步骤

### 步骤 1: 创建扩展目录结构

```bash
extensions/mychannel/
├── src/
│   ├── channel.ts          # 通道插件定义
│   ├── config.ts           # 配置处理
│   ├── messaging.ts        # 消息处理
│   ├── outbound.ts         # 消息发送
│   ├── security.ts         # 安全控制
│   └── runtime.ts          # 运行时状态
├── index.ts                # 插件入口
├── package.json
└── tsconfig.json
```

### 步骤 2: 创建 package.json

```json
{
  "name": "@openclaw/mychannel",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "openclaw": {
    "extensions": ["./index.ts"]
  },
  "dependencies": {
    "openclaw": "workspace:*"
  }
}
```

### 步骤 3: 实现通道插件

#### 3.1 通道定义 (`src/channel.ts`)

```typescript
import type { ChannelPlugin } from "openclaw/plugin-sdk/core";

export const mychannelPlugin: ChannelPlugin = {
  id: "mychannel",
  meta: {
    id: "mychannel",
    label: "MyChannel",
    selectionLabel: "MyChannel (Bot API)",
    docsPath: "/channels/mychannel",
    blurb: "通过 MyChannel 进行消息交互",
    systemImage: "message",
  },
  capabilities: {
    chatTypes: ["dm", "group"],
    polls: false,
    reactions: true,
    edit: false,
    unsend: false,
    reply: true,
    media: true,
  },
  config: {
    listAccountIds: (cfg) => {
      const accounts = cfg.channels?.mychannel?.accounts || [];
      return accounts.map(a => a.id);
    },
    resolveAccount: (cfg, accountId) => {
      const accounts = cfg.channels?.mychannel?.accounts || [];
      return accounts.find(a => a.id === accountId);
    },
    isConfigured: (account) => {
      return !!account?.botToken;
    },
  },
  gateway: {
    start: async (ctx) => {
      // 启动 WebSocket/轮询监听
      // ctx.account 包含账户配置
      // ctx.log.info() 记录日志
    },
    stop: async (ctx) => {
      // 停止监听，清理资源
    },
  },
  messaging: {
    // 处理收到的消息
  },
  outbound: {
    deliveryMode: "direct",
    sendText: async (ctx) => {
      // ctx.to - 目标用户/群组 ID
      // ctx.text - 消息文本
      // ctx.account - 账户配置
      // 返回发送结果
      return { ok: true, messageId: "..." };
    },
  },
  security: {
    resolveDmPolicy: (ctx) => {
      return {
        policy: "pairing", // pairing | allowlist | open | disabled
        allowFrom: ctx.cfg.channels?.mychannel?.allowFrom,
        allowFromPath: "channels.mychannel.allowFrom",
        approveHint: "openclaw pairing approve mychannel <CODE>",
      };
    },
  },
};
```

#### 3.2 插件入口 (`index.ts`)

```typescript
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/core";
import { mychannelPlugin } from "./src/channel.js";

const plugin = {
  id: "mychannel",
  name: "MyChannel",
  description: "MyChannel 消息通道插件",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    api.registerChannel({ plugin: mychannelPlugin });
  },
};

export default plugin;
```

### 步骤 4: 注册到 Gateway

#### 4.1 添加到通道注册表 (`src/channels/registry.ts`)

```typescript
export const CHAT_CHANNEL_ORDER = [
  "telegram",
  "whatsapp",
  "mychannel",  // 添加你的通道
  // ...
] as const;

export const CHAT_CHANNEL_META: Record<ChatChannelId, ChannelMeta> = {
  // ...
  mychannel: {
    id: "mychannel",
    label: "MyChannel",
    selectionLabel: "MyChannel (Bot API)",
    docsPath: "/channels/mychannel",
    blurb: "通过 MyChannel 进行消息交互",
    systemImage: "message",
  },
};
```

#### 4.2 添加类型定义

```typescript
// 在 types 中添加你的通道 ID
export type ChatChannelId =
  | "telegram"
  | "whatsapp"
  | "mychannel"  // 你的通道
  | (string & {});
```

### 步骤 5: 配置 Schema (可选但推荐)

```typescript
import { z } from "zod";

export const MyChannelConfigSchema = z.object({
  enabled: z.boolean().default(true),
  accounts: z.array(z.object({
    id: z.string(),
    name: z.string().optional(),
    botToken: z.string(),
    apiEndpoint: z.string().optional(),
  })),
  allowFrom: z.array(z.string()).optional(),
  dmPolicy: z.enum(["pairing", "allowlist", "open", "disabled"]).default("pairing"),
  groups: z.record(z.object({
    requireMention: z.boolean().default(true),
  })).optional(),
});
```

## 消息处理流程

### 入站消息（用户 → OpenClaw）

```typescript
// messaging.ts
import type { MessageContext } from "openclaw/plugin-sdk/core";

export async function processIncomingMessage(
  rawMessage: MyChannelMessage,
  ctx: ChannelGatewayContext
): Promise<MessageContext> {
  return {
    channelId: "mychannel",
    accountId: ctx.accountId,
    chatType: rawMessage.isGroup ? "group" : "dm",
    senderId: String(rawMessage.from.id),
    senderName: rawMessage.from.name,
    groupId: rawMessage.chat?.id,
    messageId: String(rawMessage.id),
    text: rawMessage.text,
    timestamp: rawMessage.timestamp,
    // 媒体内容
    attachments: rawMessage.attachments?.map(a => ({
      type: a.type,
      url: a.url,
      mimeType: a.mimeType,
    })),
  };
}
```

### 出站消息（OpenClaw → 用户）

```typescript
// outbound.ts
export async function sendTextMessage(
  ctx: ChannelOutboundContext
): Promise<OutboundDeliveryResult> {
  try {
    const response = await fetch(`${ctx.account.apiEndpoint}/send`, {
      method: "POST",
      headers: {
        "Authorization": `Bot ${ctx.account.botToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to: ctx.to,
        text: ctx.text,
        replyToId: ctx.replyToId,
      }),
    });

    if (!response.ok) {
      throw new Error(`发送失败：${response.status}`);
    }

    const result = await response.json();
    return {
      ok: true,
      messageId: result.messageId,
    };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}
```

## 完整示例：简单的 Webhook 通道

下面是一个完整的简化示例，展示如何实现一个基于 Webhook 的通道：

```typescript
// extensions/webhook-channel/src/channel.ts
import type { ChannelPlugin } from "openclaw/plugin-sdk/core";
import express from "express";

export const webhookChannelPlugin: ChannelPlugin = {
  id: "webhook",
  meta: {
    id: "webhook",
    label: "Webhook",
    selectionLabel: "Custom Webhook",
    docsPath: "/channels/webhook",
    blurb: "通过自定义 Webhook 接收和发送消息",
  },
  capabilities: {
    chatTypes: ["dm"],
    reply: true,
    media: false,
  },
  config: {
    listAccountIds: (cfg) => Object.keys(cfg.channels?.webhook?.endpoints || {}),
    resolveAccount: (cfg, accountId) => cfg.channels?.webhook?.endpoints?.[accountId],
    isConfigured: (account) => !!account?.webhookPath,
  },
  gateway: {
    start: async (ctx) => {
      // 注册 Webhook 端点
      ctx.runtime.express?.use(
        ctx.account.webhookPath,
        express.json(),
        async (req, res) => {
          try {
            // 处理入站消息
            const message = {
              channelId: "webhook",
              accountId: ctx.accountId,
              senderId: req.body.senderId || "unknown",
              text: req.body.text,
              // ...
            };

            // 转发到 Gateway
            await ctx.deliverMessage(message);

            res.json({ ok: true });
          } catch (err) {
            res.status(500).json({ error: err.message });
          }
        }
      );

      ctx.log.info(`Webhook 已注册：${ctx.account.webhookPath}`);
    },
    stop: async (ctx) => {
      // 清理 Webhook
    },
  },
  outbound: {
    deliveryMode: "gateway",
    sendText: async (ctx) => {
      // 通过 HTTP POST 发送消息
      const response = await fetch(ctx.account.callbackUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          to: ctx.to,
          text: ctx.text,
        }),
      });

      return response.ok
        ? { ok: true }
        : { ok: false, error: `发送失败：${response.status}` };
    },
  },
  security: {
    resolveDmPolicy: (ctx) => ({
      policy: ctx.cfg.channels?.webhook?.dmPolicy || "pairing",
      allowFrom: ctx.cfg.channels?.webhook?.allowFrom,
      allowFromPath: "channels.webhook.allowFrom",
      approveHint: "openclaw pairing approve webhook <CODE>",
    }),
  },
};
```

## 测试与调试

### 单元测试

```typescript
// src/channel.test.ts
import { describe, it, expect } from "vitest";
import { webhookChannelPlugin } from "./channel.js";

describe("webhookChannelPlugin", () => {
  it("应正确解析配置", () => {
    const config = {
      channels: {
        webhook: {
          endpoints: {
            test: { webhookPath: "/webhook/test" },
          },
        },
      },
    };

    const accountIds = webhookChannelPlugin.config.listAccountIds(config);
    expect(accountIds).toContain("test");
  });
});
```

### 运行测试

```bash
# 运行通道测试
pnpm test extensions/webhook-channel

# 类型检查
pnpm tsgo extensions/webhook-channel

#  lint
pnpm lint extensions/webhook-channel
```

## 配置示例

在 `config.json` 中添加你的通道配置：

```json5
{
  "channels": {
    "mychannel": {
      "enabled": true,
      "dmPolicy": "pairing",
      "allowFrom": ["user123", "user456"],
      "accounts": [
        {
          "id": "main",
          "name": "主账户",
          "botToken": "your-bot-token-here",
          "apiEndpoint": "https://api.mychannel.com"
        }
      ],
      "groups": {
        "*": {
          "requireMention": true
        }
      }
    }
  }
}
```

## 常见问题

### Q: 如何选择 `deliveryMode`？

- **`direct`**: 通道直接发送消息（推荐，简单直接）
- **`gateway`**: 通过 Gateway 统一发送（适合需要统一处理的场景）
- **`hybrid`**: 混合模式（某些情况 direct，某些 gateway）

### Q: 如何处理媒体消息？

实现 `sendMedia` 方法，处理流程：

1. 从 `ctx.mediaUrl` 获取媒体 URL
2. 下载媒体文件（可能需要认证）
3. 调用通道的媒体上传 API
4. 返回发送结果

### Q: 如何支持群组？

1. 在 `capabilities` 中声明 `chatTypes: ["dm", "group"]`
2. 实现 `groups` 适配器处理群组策略
3. 实现 `mentions` 适配器处理提及逻辑

### Q: 配对 (Pairing) 如何工作？

配对模式流程：

1. 陌生用户发送消息
2. 通道生成配对码（`issuePairingChallenge`）
3. 回复配对码给用户
4. 管理员运行 `openclaw pairing approve mychannel <CODE>`
5. 用户被加入白名单，后续消息正常处理

## 下一步

实现通道后：

1. **更新文档** - 在 `docs/channels/` 添加通道文档
2. **添加 CLI 命令** - 可选的 `openclaw mychannel ...` 命令
3. **发布插件** - 发布到 npm (`@openclaw/mychannel`)
4. **更新注册表** - 确保在 `CHAT_CHANNEL_ORDER` 中注册

## 参考资源

- 现有通道实现：`src/telegram/`, `src/discord/`, `src/slack/`
- 扩展示例：`extensions/voice-call/`, `extensions/matrix/`
- Plugin SDK 类型：`src/channels/plugins/types.ts`
- 通道注册：`src/channels/registry.ts`

## 相关文档链接

- https://docs.openclaw.ai/channels
- https://docs.openclaw.ai/tools/plugin
- https://docs.openclaw.ai/gateway/security
