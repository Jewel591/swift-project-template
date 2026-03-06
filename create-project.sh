#!/bin/bash
set -euo pipefail

# ============================================================
# Swift 项目模板 - 重命名脚本
# 用法: ./create-project.sh <ProjectName> [org_id]
#
# 在 GitHub "Use this template" 克隆后运行，
# 将 Talon 就地重命名为新项目名。
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OLD_NAME="Talon"
DEFAULT_ORG_ID="com.linliao"

# 参数解析
if [ $# -lt 1 ]; then
    echo "用法: $0 <ProjectName> [org_id]"
    echo ""
    echo "  ProjectName    新项目名称（仅字母数字，如 MyAwesomeApp）"
    echo "  org_id         组织标识符（默认: com.linliao）"
    echo ""
    echo "示例:"
    echo "  $0 MyApp"
    echo "  $0 MyApp com.example"
    exit 1
fi

NEW_NAME="$1"
ORG_ID="${2:-$DEFAULT_ORG_ID}"

# 验证项目名称
if [[ ! "$NEW_NAME" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
    echo "❌ 项目名称必须以字母开头，仅包含字母和数字。"
    exit 1
fi

# 检查模板目录是否存在
if [ ! -d "$SCRIPT_DIR/$OLD_NAME" ]; then
    echo "❌ 模板目录 '$SCRIPT_DIR/$OLD_NAME' 不存在，可能已经重命名过了。"
    exit 1
fi

echo "🚀 正在重命名项目 '$OLD_NAME' → '$NEW_NAME'..."
echo "   Bundle ID: $ORG_ID.$NEW_NAME"
echo ""

# 1. 清理 Xcode 缓存和用户数据
rm -rf "$SCRIPT_DIR/$OLD_NAME.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
rm -rf "$SCRIPT_DIR/$OLD_NAME.xcodeproj/xcuserdata"
find "$SCRIPT_DIR" -name ".DS_Store" -delete
find "$SCRIPT_DIR" -name ".gitkeep" -delete

# 2. 重命名目录（从深到浅，避免路径失效）
find "$SCRIPT_DIR" -depth -name "*$OLD_NAME*" -not -path "*/.git/*" -print0 | while IFS= read -r -d '' path; do
    dir=$(dirname "$path")
    base=$(basename "$path")
    new_base="${base//$OLD_NAME/$NEW_NAME}"
    if [ "$base" != "$new_base" ]; then
        mv "$path" "$dir/$new_base"
    fi
done

# 3. 替换文件内容
find "$SCRIPT_DIR" -type f \( \
    -name "*.swift" \
    -o -name "*.pbxproj" \
    -o -name "*.plist" \
    -o -name "*.xcscheme" \
    -o -name "*.json" \
    -o -name "*.md" \
    -o -name "*.xcstrings" \
    -o -name "*.entitlements" \
    -o -name "*.yml" \
    -o -name "*.yaml" \
\) -not -path "*/.git/*" -print0 | while IFS= read -r -d '' file; do
    # 替换组织标识符（仅当不同时）
    if [ "$ORG_ID" != "$DEFAULT_ORG_ID" ]; then
        if grep -q "$DEFAULT_ORG_ID" "$file" 2>/dev/null; then
            sed -i '' "s/$DEFAULT_ORG_ID/$ORG_ID/g" "$file"
        fi
    fi
    # 替换项目名称
    if grep -q "$OLD_NAME" "$file" 2>/dev/null; then
        sed -i '' "s/$OLD_NAME/$NEW_NAME/g" "$file"
    fi
done

# 4. 删除脚本自身（一次性使用）
rm -f "$SCRIPT_DIR/create-project.sh"

echo "✅ 重命名完成！"
echo ""
echo "   📦 Bundle ID: $ORG_ID.$NEW_NAME"
echo ""
echo "后续步骤:"
echo "   1. open '$NEW_NAME.xcodeproj'"
echo "   2. 等待 SPM 依赖 resolve 完成"
echo "   3. 编辑 CLAUDE.md 填写项目信息"
echo "   4. 编辑 .mcp.json 填写 API Key"
