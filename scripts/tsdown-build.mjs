#!/usr/bin/env node

import { spawnSync } from "node:child_process";

const logLevel = process.env.OPENCLAW_BUILD_VERBOSE ? "info" : "warn";

// 增加内存限制，低内存环境下使用串行构建
const nodeOptions = ["--max-old-space-size=4096"];

const result = spawnSync(
  "pnpm",
  ["exec", "tsdown", "--config-loader", "unrun", "--logLevel", logLevel],
  {
    stdio: "inherit",
    shell: process.platform === "win32",
    env: {
      ...process.env,
      NODE_OPTIONS: nodeOptions.join(" "),
    },
  },
);

if (typeof result.status === "number") {
  process.exit(result.status);
}

process.exit(1);
