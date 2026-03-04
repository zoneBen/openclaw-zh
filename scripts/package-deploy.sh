#!/bin/bash
# OpenClaw 部署包打包脚本

set -e

# 切换到项目根目录
cd "$(dirname "$0")/.."

DEPLOY_DIR="/tmp/openclaw-deploy"
OUTPUT_DIR="/tmp"

echo "=== OpenClaw 部署包打包脚本 ==="

# 清理旧目录
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# 复制必要文件
echo "复制 dist 目录..."
cp -r dist "$DEPLOY_DIR/"

echo "复制 UI 文件..."
cp -r ui/dist/control-ui "$DEPLOY_DIR/dist/" 2>/dev/null || {
    echo "UI 文件不存在，跳过..."
}

echo "复制配置文件..."
cp package.json "$DEPLOY_DIR/"
cp openclaw.mjs "$DEPLOY_DIR/"
cp LICENSE "$DEPLOY_DIR/" 2>/dev/null || true
cp README.md "$DEPLOY_DIR/" 2>/dev/null || true

# 创建精简的 node_modules (只包含运行时依赖)
echo "准备运行时依赖..."
if [ -d "node_modules" ]; then
    mkdir -p "$DEPLOY_DIR/node_modules"

    # 复制核心依赖
    for pkg in @mariozechner @grammyjs @slack @discordjs @whiskeysockets baileys grammy \
               chalk commander croner dotenv express jiti json5 ws yaml zod \
               tsx tslog undici tar sharp file-type jszip ajv gaxios \
               @aws-sdk @mozilla/readability @sinclair/typebox \
               @homebridge/ciao @lydell/node-pty @buape/carbon \
               @clack/prompts osc-progress qrcode-terminal linkedom \
               node-edge-tts opusscript pdfjs-dist playwright-core \
               sqlite-vec dotenv markdown-it long node-domexception; do
        if [ -d "node_modules/$pkg" ]; then
            cp -r "node_modules/$pkg" "$DEPLOY_DIR/node_modules/" 2>/dev/null || true
        fi
    done

    echo "node_modules 大小：$(du -sh "$DEPLOY_DIR/node_modules" | cut -f1)"
fi

# 创建部署说明
cat > "$DEPLOY_DIR/README-DEPLOY.txt" << 'EOF'
OpenClaw 部署包
==============

部署步骤:
1. 确保目标电脑已安装 Node.js 22+
2. 将此目录复制到目标位置，如 /opt/openclaw
3. 运行：node openclaw.mjs onboard --install-daemon
4. 启动：node openclaw.mjs gateway --port 18789

访问 Dashboard: http://localhost:18789/control-ui/

详细配置请参考 DEPLOY.md
EOF

# 压缩
echo "创建压缩包..."
cd /tmp
tar -czf "$OUTPUT_DIR/openclaw-deploy-$(date +%Y%m%d).tar.gz" openclaw-deploy/

# 显示结果
echo ""
echo "=== 打包完成 ==="
echo "输出文件：$OUTPUT_DIR/openclaw-deploy-$(date +%Y%m%d).tar.gz"
echo "文件大小：$(du -h "$OUTPUT_DIR/openclaw-deploy-$(date +%Y%m%d).tar.gz" | cut -f1)"
echo ""
echo "部署目录结构:"
du -sh "$DEPLOY_DIR"/*
echo ""
echo "复制到目标电脑命令:"
echo "  scp $OUTPUT_DIR/openclaw-deploy-$(date +%Y%m%d).tar.gz user@target-host:/opt/"
