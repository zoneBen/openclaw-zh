#!/bin/bash
# OpenClaw 一键构建脚本
# 支持本地快速构建 UI 和核心代码
# 支持打包发布到另一台电脑运行

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# 检查 Node.js 版本
check_node_version() {
    log_info "检查 Node.js 版本..."
    NODE_VERSION=$(node -v 2>/dev/null || echo "not installed")
    if [ "$NODE_VERSION" = "not installed" ]; then
        log_error "Node.js 未安装，请安装 Node.js 22+"
        exit 1
    fi

    # 提取主版本号
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d'.' -f1)
    if [ "$NODE_MAJOR" -lt 22 ]; then
        log_error "Node.js 版本过低 (当前：$NODE_VERSION)，请升级到 Node.js 22+"
        exit 1
    fi
    log_success "Node.js 版本：$NODE_VERSION"
}

# 检查 pnpm
check_pnpm() {
    log_info "检查 pnpm..."
    if ! command -v pnpm &> /dev/null; then
        log_error "pnpm 未安装，请运行：npm install -g pnpm"
        exit 1
    fi
    log_success "pnpm 已安装"
}

# 安装依赖
install_deps() {
    log_info "安装依赖..."
    cd "$ROOT_DIR"
    pnpm install
    log_success "依赖安装完成"
}

# 构建 UI
build_ui() {
    log_step "构建 UI..."
    cd "$ROOT_DIR"
    pnpm ui:build
    if [ -d "$ROOT_DIR/dist/control-ui" ]; then
        UI_SIZE=$(du -sh "$ROOT_DIR/dist/control-ui" 2>/dev/null | cut -f1)
        log_success "UI 构建完成 (大小：$UI_SIZE)"
    else
        log_warn "UI 构建完成但未找到 dist/control-ui 目录"
    fi
}

# 构建核心代码 (快速模式 - 跳过部分步骤)
build_core_fast() {
    log_step "快速构建核心代码..."
    cd "$ROOT_DIR"

    # 1. 打包 a2ui
    log_info "打包 a2ui..."
    pnpm canvas:a2ui:bundle

    # 2. 编译 TypeScript (增加内存限制) - 先于 UI 构建
    log_info "编译 TypeScript..."
    export NODE_OPTIONS="--max-old-space-size=4096"
    node scripts/tsdown-build.mjs

    # 3. 复制 plugin-sdk 别名
    log_info "复制 plugin-sdk 别名..."
    node scripts/copy-plugin-sdk-root-alias.mjs

    # 4. 生成 plugin-sdk 类型定义
    log_info "生成 plugin-sdk 类型定义..."
    pnpm build:plugin-sdk:dts

    # 5. 写入 plugin-sdk 入口 DTS
    log_info "写入 plugin-sdk 入口 DTS..."
    node --import tsx scripts/write-plugin-sdk-entry-dts.ts

    # 6. 复制 a2ui 到 dist
    log_info "复制 a2ui 到 dist..."
    node --import tsx scripts/canvas-a2ui-copy.ts

    # 7. 写入构建信息
    log_info "写入构建信息..."
    node --import tsx scripts/write-build-info.ts

    log_success "核心代码快速构建完成"
}

# 完整构建
build_full() {
    log_step "完整构建..."
    cd "$ROOT_DIR"
    export NODE_OPTIONS="--max-old-space-size=4096"
    pnpm build
    log_success "完整构建完成"
}

# 运行检查
run_checks() {
    log_step "运行代码检查..."
    cd "$ROOT_DIR"
    pnpm lint
    log_success "代码检查完成"
}

# 打包发布包
create_release_package() {
    local OUTPUT_NAME="${1:-openclaw-release.tar.gz}"
    local OUTPUT_PATH="$ROOT_DIR/$OUTPUT_NAME"

    log_step "创建发布包..."
    cd "$ROOT_DIR"

    # 检查 dist 目录是否存在
    if [ ! -d "$ROOT_DIR/dist" ]; then
        log_error "dist 目录不存在，请先运行构建"
        exit 1
    fi

    # 检查 UI 是否已构建
    if [ ! -d "$ROOT_DIR/dist/control-ui" ]; then
        log_warn "dist/control-ui 不存在，UI 可能未构建"
        log_info "建议先运行：$0 --ui-only"
    fi

    # 定义需要打包的文件和目录
    # 根据 package.json 的 files 字段 + 运行时需要的文件
    local FILES_TO_PACK=(
        # 入口文件
        "openclaw.mjs"

        # 编译输出
        "dist/"

        # 插件和扩展
        "extensions/"
        "skills/"

        # 资源文件
        "assets/"

        # 文档
        "docs/"

        # 配置文件
        "package.json"
        "pnpm-lock.yaml"

        # README 和许可证
        "README.md"
        "LICENSE"
        "CHANGELOG.md"
        "README-header.png"

        # 其他运行时需要的文件
        ".github/"
        "scripts/"
    )

    # 创建临时目录
    local TEMP_DIR=$(mktemp -d)
    local PACK_DIR="$TEMP_DIR/openclaw"
    mkdir -p "$PACK_DIR"

    log_info "复制文件到临时目录..."

    # 复制文件
    for item in "${FILES_TO_PACK[@]}"; do
        if [ -e "$ROOT_DIR/$item" ]; then
            log_info "  打包：$item"
            cp -r "$ROOT_DIR/$item" "$PACK_DIR/" 2>/dev/null || true
        else
            log_warn "  跳过 (不存在): $item"
        fi
    done

    # 创建 node_modules 安装脚本
    cat > "$PACK_DIR/INSTALL.md" << 'EOF'
# OpenClaw 部署指南

## 快速部署

```bash
# 1. 安装 Node.js 22+
node -v  # 确认版本 >= 22.0.0

# 2. 安装 pnpm
npm install -g pnpm

# 3. 安装依赖
pnpm install --prod  # 或 npm install --omit=dev

# 4. 运行
node openclaw.mjs --help
pnpm openclaw --help

# 5. 启动网关
pnpm openclaw gateway run
```

## Docker 部署

```bash
docker run -p 18789:18789 ghcr.io/zoneben/openclaw-zh:zh-cn
```

## 文件说明

- `dist/` - 编译后的代码
- `dist/control-ui/` - Web 管理界面
- `extensions/` - 频道扩展
- `skills/` - 技能包
- `assets/` - 资源文件
- `docs/` - 文档
- `scripts/` - 构建和工具脚本
EOF

    # 创建部署脚本
    cat > "$PACK_DIR/deploy.sh" << 'EOF'
#!/bin/bash
# OpenClaw 部署脚本

set -e

echo "========================================"
echo "  OpenClaw 部署脚本"
echo "========================================"

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "[ERROR] Node.js 未安装"
    echo "请先安装 Node.js 22+: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node -v)
NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d'.' -f1)
if [ "$NODE_MAJOR" -lt 22 ]; then
    echo "[ERROR] Node.js 版本过低：$NODE_VERSION"
    echo "请升级到 Node.js 22+"
    exit 1
fi
echo "[OK] Node.js: $NODE_VERSION"

# 检查 pnpm
if ! command -v pnpm &> /dev/null; then
    echo "[INFO] pnpm 未安装，正在安装..."
    npm install -g pnpm
fi
echo "[OK] pnpm: $(pnpm -v)"

# 安装依赖
echo "[STEP] 安装依赖..."
pnpm install --prod

echo ""
echo "========================================"
echo "  部署完成!"
echo "========================================"
echo ""
echo "运行命令:"
echo "  node openclaw.mjs --help"
echo "  pnpm openclaw gateway run"
echo ""
EOF
    chmod +x "$PACK_DIR/deploy.sh"

    # 计算大小
    log_info "计算打包大小..."
    local SIZE=$(du -sh "$PACK_DIR" | cut -f1)
    log_info "预计大小：$SIZE"

    # 创建 tar.gz
    log_info "创建压缩包：$OUTPUT_PATH"
    tar -czf "$OUTPUT_PATH" -C "$TEMP_DIR" openclaw

    # 清理临时目录
    rm -rf "$TEMP_DIR"

    # 显示结果
    local FINAL_SIZE=$(du -sh "$OUTPUT_PATH" | cut -f1)
    log_success "发布包创建完成：$OUTPUT_PATH (大小：$FINAL_SIZE)"
    echo ""
    echo "部署到另一台电脑:"
    echo "  1. 复制 $OUTPUT_NAME 到目标电脑"
    echo "  2. tar -xzf $OUTPUT_NAME"
    echo "  3. cd openclaw && ./deploy.sh"
}

# 显示帮助
show_help() {
    cat << EOF
OpenClaw 一键构建脚本

用法：$(basename "$0") [选项]

构建选项:
  -f, --fast        快速构建 (跳过部分可选步骤)
  -F, --full        完整构建 (包含所有步骤)
  -u, --ui-only     仅构建 UI
  -c, --core-only   仅构建核心代码

打包选项:
  -p, --package     创建发布包
  -o, --output      指定发布包文件名 (默认：openclaw-release.tar.gz)

其他选项:
  --skip-deps       跳过依赖安装
  --no-check        跳过代码检查
  -h, --help        显示帮助信息

示例:
  $(basename "$0")              # 默认快速构建
  $(basename "$0") --fast       # 快速构建
  $(basename "$0") --full       # 完整构建
  $(basename "$0") --ui-only    # 仅构建 UI
  $(basename "$0") -p           # 构建并创建发布包
  $(basename "$0") -p -o my-release.tar.gz  # 指定文件名
  $(basename "$0") -c --skip-deps  # 仅构建核心代码，跳过依赖安装

部署说明:
  构建后，使用 -p 选项创建发布包，然后复制到目标电脑:
  1. tar -xzf openclaw-release.tar.gz
  2. cd openclaw
  3. ./deploy.sh

EOF
}

# 主函数
main() {
    BUILD_MODE="fast"
    SKIP_DEPS=false
    SKIP_CHECK=false
    UI_ONLY=false
    CORE_ONLY=false
    CREATE_PACKAGE=false
    OUTPUT_NAME="openclaw-release.tar.gz"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--fast)
                BUILD_MODE="fast"
                shift
                ;;
            -F|--full)
                BUILD_MODE="full"
                shift
                ;;
            -u|--ui-only)
                UI_ONLY=true
                shift
                ;;
            -c|--core-only)
                CORE_ONLY=true
                shift
                ;;
            -p|--package)
                CREATE_PACKAGE=true
                shift
                ;;
            -o|--output)
                OUTPUT_NAME="$2"
                shift 2
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --no-check)
                SKIP_CHECK=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项：$1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "========================================"
    echo "  OpenClaw 构建脚本"
    echo "========================================"
    echo ""

    # 检查环境
    check_node_version
    check_pnpm

    # 安装依赖 (除非跳过)
    if [ "$SKIP_DEPS" = false ]; then
        install_deps
    fi

    # 根据模式构建
    if [ "$UI_ONLY" = true ]; then
        build_ui
    elif [ "$CORE_ONLY" = true ]; then
        build_core_fast
    elif [ "$BUILD_MODE" = "full" ]; then
        build_full
    else
        # 默认快速构建 (先核心后 UI，避免 UI 被清空)
        build_core_fast
        build_ui
    fi

    # 运行检查 (除非跳过)
    if [ "$SKIP_CHECK" = false ]; then
        run_checks
    fi

    # 创建发布包 (如果请求)
    if [ "$CREATE_PACKAGE" = true ]; then
        create_release_package "$OUTPUT_NAME"
    fi

    echo ""
    echo "========================================"
    log_success "构建完成!"
    echo "========================================"
}

main "$@"
