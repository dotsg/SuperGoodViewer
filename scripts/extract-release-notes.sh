#!/usr/bin/env bash
set -euo pipefail

# Extract release title and formatted release body from CHANGELOG.md for a given tag (e.g. v1.1.2).
# Usage:
#   ./scripts/extract-release-notes.sh <version_tag> --title
#   ./scripts/extract-release-notes.sh <version_tag> --notes
#   ./scripts/extract-release-notes.sh <version_tag> --body

VERSION_TAG="${1:-}"
MODE="${2:---body}"

if [[ -z "$VERSION_TAG" ]]; then
  echo "Usage: $0 <version_tag> [--title|--notes|--body]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "Error: CHANGELOG.md not found at $CHANGELOG_FILE" >&2
  exit 1
fi

# Extract heading line matching "## vX.Y.Z..."
HEADING_LINE="$(grep -m1 -E "^## ${VERSION_TAG}([[:space:]]|$)" "$CHANGELOG_FILE" || true)"

if [[ -n "$HEADING_LINE" ]]; then
  RELEASE_TITLE="${HEADING_LINE#\#\# }"
else
  RELEASE_TITLE="${VERSION_TAG}"
fi

if [[ "$MODE" == "--title" ]]; then
  printf '%s\n' "$RELEASE_TITLE"
  exit 0
fi

# Extract section body between "## <VERSION_TAG>" and the next "## v" heading
RAW_NOTES="$(awk -v tag="$VERSION_TAG" '
  $0 ~ "^## " tag "([[:space:]]|$)" { found=1; next }
  found && /^## v[0-9]+\./ { exit }
  found { print }
' "$CHANGELOG_FILE")"

# Trim leading and trailing blank lines
CLEAN_NOTES="$(printf '%s\n' "$RAW_NOTES" | awk '
  NF {
    if (seen) {
      for (i = 0; i < blanks; i++) print ""
    }
    seen = 1
    blanks = 0
    print
    next
  }
  seen { blanks++ }
')"

if [[ -z "$CLEAN_NOTES" ]]; then
  CLEAN_NOTES="包含性能优化、排版增强与稳定性提升。"
fi

if [[ "$MODE" == "--notes" ]]; then
  printf '%s\n' "$CLEAN_NOTES"
  exit 0
fi

cat <<EOF
${CLEAN_NOTES}

---

<details>
<summary><b>📦 下载与安装指南（macOS / Windows / Linux）</b></summary>

#### 🍏 macOS 用户
- **Apple Silicon (M 系列芯片，M1/M2/M3/M4 等)**：下载 \`SuperGoodViewer-${VERSION_TAG}-macos-arm64.dmg\`（原生极致性能与超轻体积）
- **Intel 处理器 Mac**：下载 \`SuperGoodViewer-${VERSION_TAG}-macos-x64.dmg\`
- **系统要求**：macOS 11.0+
- **芯片类型查看方法**：点击屏幕左上角苹果图标  ->「关于本机」（About This Mac）查看芯片类型，或在终端运行 \`uname -m\`（输出 \`arm64\` 对应 Apple Silicon，输出 \`x86_64\` 对应 Intel）。
- **⚠️ v1.0.7 及更早版本的 Intel Mac 用户请注意**：旧版内置更新器未包含双架构识别，可能误下载 Apple Silicon 安装包导致更新后无法启动。请**直接在此页面手动下载** \`SuperGoodViewer-${VERSION_TAG}-macos-x64.dmg\` 覆盖安装升级，升级至新版后即可恢复正常自动更新。
- **首次打开提示处理**：
  若系统提示「*无法验证开发者*」或「*已损坏，无法打开*」，请打开终端（Terminal）执行以下命令解除隔离属性即可：
  \`\`\`bash
  xattr -cr /Applications/SuperGoodViewer.app
  \`\`\`

#### 🪟 Windows 用户
- **Intel / AMD 64位 PC**：下载 \`SuperGoodViewer-${VERSION_TAG}-windows-x64.zip\`
- **高通骁龙 X / Surface 等 ARM64 设备**：下载 \`SuperGoodViewer-${VERSION_TAG}-windows-arm64.zip\`（100% 纯原生 Native ARM64 架构，零转译开销与超高能效）
- **使用方式**：解压 zip 包至任意目录，双击 \`SuperGoodViewer.exe\` 即可即开即用（绿色免安装便携版）；亦可将解压目录加入系统环境变量或使用内置的 \`sgv.cmd\` / \`sgv.ps1\` 命令行工具快速预览文档。
- **首次运行提示**：如遇 Windows SmartScreen 提示拦截，点击「更多信息」并选择「仍要运行」。

#### 🐧 Linux 用户
- **Intel / AMD 64位 Linux (x86_64 / amd64)**：下载 \`SuperGoodViewer-${VERSION_TAG}-linux-amd64.tar.gz\`
- **ARM64 Linux（树莓派 4/5、Apple Silicon Linux 虚拟机、ARM 云服务器等）**：下载 \`SuperGoodViewer-${VERSION_TAG}-linux-arm64.tar.gz\`（纯原生 ARM64 极致体验）
- **系统要求**：glibc ≥ 2.35（Ubuntu 22.04+、Debian 12+ / Raspberry Pi OS Bookworm、Fedora、Arch Linux 等主流 64 位发行版，需安装 GTK 3 环境）
- **使用方式**：解压 tar.gz 归档至任意目录，运行 \`./supergoodviewer\` 即可直接启动（绿色免安装）；亦可将解压目录中的 \`bin/sgv\` 脚本软链接至 \`~/.local/bin/sgv\`，在终端随时以命令行唤起。

</details>
EOF
