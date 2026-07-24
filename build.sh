#!/bin/bash
set -e

# ===== SFTP Gen ビルドスクリプト (Mac直接配布) =====

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MAC_BUILD_DIR="mac/build"
APP_NAME="sftp-gen"
DMG_NAME="${APP_NAME}_mac.dmg"
ZIP_NAME="${APP_NAME}_mac.zip"
DIST_DIR="../apps.tomippe.jp/sftp-gen"
APP_BUNDLE_FILE="SFTP Generator.app"
SIGNING_IDENTITY="Developer ID Application: TOMIHIDE OTA (4U63Y3X98K)"
KEYCHAIN_PROFILE="TOMIHIDE OTA"
BUNDLE_ID="jp.tomippe.sftpgen"
MAC_DIST_SLUG="sftp-gen"
MAC_DIST_MANIFEST_NAME="SFTPGen"

source "$SCRIPT_DIR/../build-common/version.sh"
source "$SCRIPT_DIR/../build-common/ftp-upload.sh"
source "$SCRIPT_DIR/../build-common/git-commit.sh"
source "$SCRIPT_DIR/../build-common/mac-sparkle-lib.sh"
source "$SCRIPT_DIR/../build-common/mac-sparkle-dist.sh"

APP_ONLY=false
COMMIT_MSG=""
NO_VERUP=false
while [ $# -gt 0 ]; do
    case "$1" in
        -app) APP_ONLY=true ;;
        -cm) shift; COMMIT_MSG="$1" ;;
        -noverup) NO_VERUP=true ;;
    esac
    shift || true
done

VERSION=$(version_read)
if [ -f "package.json" ]; then
    echo "📝 version.txt のバージョン ${VERSION} を package.json に反映します..."
    python3 -c "
import json
from pathlib import Path
p = Path('package.json')
data = json.loads(p.read_text(encoding='utf-8'))
data['version'] = '${VERSION}'
p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
"
fi

echo "🚀 ${APP_NAME} v${VERSION} のビルドを開始します..."

# Sparkle（disk-monitor から初回コピー — git 管理外）
if [ ! -f "mac/Sparkle.framework/Versions/B/Sparkle" ]; then
    if [ -f "../disk-monitor/mac/Sparkle.framework/Versions/B/Sparkle" ]; then
        echo "📦 Sparkle.framework / Sparkle_bin を disk-monitor からコピー..."
        mkdir -p mac
        ditto --norsrc "../disk-monitor/mac/Sparkle.framework" "mac/Sparkle.framework"
        ditto --norsrc "../disk-monitor/mac/Sparkle_bin" "mac/Sparkle_bin"
    else
        echo "⚠️  mac/Sparkle.framework がありません（appcast 生成はスキップ）"
    fi
fi

# DMG 背景用ロゴ
if [ ! -f "mac/AppsLogo.png" ] && [ -f "../build-common/Resources/AppsLogo.png" ]; then
    cp "../build-common/Resources/AppsLogo.png" "mac/AppsLogo.png"
fi

if [ -f "mac/icon.png" ]; then
    echo "🎨 アイコンファイルを生成中..."
    mkdir -p .tmp/icons.iconset
    sizes=(16 32 64 128 256 512 1024)
    for size in "${sizes[@]}"; do
        sips -z $size $size mac/icon.png --out ".tmp/icons.iconset/icon_${size}x${size}.png"
        if [ $size -le 512 ]; then
            sips -z $((size*2)) $((size*2)) mac/icon.png --out ".tmp/icons.iconset/icon_${size}x${size}@2x.png"
        fi
    done
    iconutil -c icns .tmp/icons.iconset -o mac/icon.icns
    rm -rf .tmp
    echo "✅ アイコンファイルの生成が完了しました"
fi

echo "🧹 キャッシュと Mac ビルドファイルを削除中..."
rm -rf "$MAC_BUILD_DIR" out/ node_modules/ ~/.electron-builder/cache/ ~/.electron/cache/ .webpack/

echo "📦 依存関係をインストール中..."
npm install --force --ignore-platform

echo "📦 macOS Universal版をビルド中..."
npm run build -- --mac --universal

MAC_APP="${MAC_BUILD_DIR}/mac-universal/${APP_BUNDLE_FILE}"
if [ ! -d "$MAC_APP" ]; then
    echo "❌ アプリバンドルが見つかりません: $MAC_APP"
    exit 1
fi
echo "✅ macOS版のビルドが完了しました"

if $APP_ONLY; then
    echo ""
    echo "✅ ${APP_NAME} v${VERSION} — ビルド完了! (-app モード)"
    echo "📁 成果物: $MAC_APP"
    exit 0
fi

DIST_DMG="${MAC_BUILD_DIR}/${DMG_NAME}"
NOTARIZE_ZIP="${MAC_BUILD_DIR}/_notarize.zip"
APPS_LOGO="mac/AppsLogo.png"
[ -f "$APPS_LOGO" ] || APPS_LOGO="$(mac_apps_logo_path)"

echo ""
echo "========== 直接配布版（DMG・公証・検査）=========="
echo ""
echo "🧹 配布前クリーンアップ（Electron 署名は electron-builder のまま）..."
mac_strip_bundle "$MAC_APP"

echo ""
echo "📤 .app を公証中（内部用 ZIP）..."
mac_create_dist_zip "$MAC_APP" "$NOTARIZE_ZIP"
mac_notarytool_submit "$NOTARIZE_ZIP" "$KEYCHAIN_PROFILE"

echo ""
echo "📎 .app にステープル中..."
xcrun stapler staple "$MAC_APP"
rm -f "$NOTARIZE_ZIP"

echo ""
echo "💿 配布 DMG を作成中..."
mac_create_dist_dmg_layout "$MAC_APP" "$DIST_DMG" "SFTP Generator" "$APPS_LOGO"
mac_sign_dist_dmg "$DIST_DMG" "$SIGNING_IDENTITY"

echo ""
echo "📤 DMG を公証中..."
mac_notarytool_submit "$DIST_DMG" "$KEYCHAIN_PROFILE"

echo ""
echo "📎 DMG にステープル中..."
xcrun stapler staple "$DIST_DMG"

echo ""
echo "🔍 配布前検査..."
mac_sparkle_publish_verify_dmg "$MAC_APP" "$DIST_DMG" "$APP_BUNDLE_FILE"

echo ""
echo "📄 latest-mac.yml を生成中..."
DMG_SIZE=$(stat -f%z "$DIST_DMG")
DMG_SHA512=$(openssl dgst -sha512 -binary "$DIST_DMG" | openssl base64 | tr -d '\n')
RELEASE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
cat > "${MAC_BUILD_DIR}/latest-mac.yml" <<EOF
version: ${VERSION}
files:
  - url: ${DMG_NAME}
    sha512: ${DMG_SHA512}
    size: ${DMG_SIZE}
path: ${DMG_NAME}
sha512: ${DMG_SHA512}
releaseDate: '${RELEASE_DATE}'
EOF

if [ -f "mac/Sparkle_bin/generate_appcast" ]; then
    echo ""
    echo "📋 appcast.xml を生成中..."
    mkdir -p "$DIST_DIR"
    rm -f "$DIST_DIR/$ZIP_NAME"
    mac_sparkle_remove_stale_remote_pkg "$MAC_DIST_SLUG" "dmg"
    cp "$DIST_DMG" "$DIST_DIR/$DMG_NAME"
    MAC_DIST_PROJECT_ROOT="$SCRIPT_DIR"
    MAC_DIST_COMMIT_MSG="$COMMIT_MSG"
    mac_sparkle_write_release_notes_html "$DIST_DIR" "$MAC_DIST_SLUG" "$VERSION" "$SCRIPT_DIR" "$COMMIT_MSG" || true
    "$SCRIPT_DIR/mac/Sparkle_bin/generate_appcast" \
        --account ed25519 \
        --download-url-prefix "https://apps.tomippe.jp/${MAC_DIST_SLUG}/" \
        --link "https://apps.tomippe.jp/${MAC_DIST_SLUG}/" \
        "$DIST_DIR"
    rm -f "$DIST_DIR/$ZIP_NAME"
    ftp_delete_file "${MAC_DIST_SLUG}/${ZIP_NAME}" 2>/dev/null || true
else
    echo ""
    echo "📂 配布用ディレクトリにコピーしています..."
    mkdir -p "$DIST_DIR"
    rm -f "$DIST_DIR/$DMG_NAME" "$DIST_DIR/$ZIP_NAME"
    cp "$DIST_DMG" "$DIST_DIR/$DMG_NAME"
fi

cp "${MAC_BUILD_DIR}/latest-mac.yml" "$DIST_DIR/latest-mac.yml"

python3 -c "
import json, os
path = '$DIST_DIR/manifest.json'
data = {}
if os.path.exists(path):
    with open(path, encoding='utf-8-sig') as f: data = json.load(f)
data['name'] = '$MAC_DIST_MANIFEST_NAME'
data['version'] = '$VERSION'
data['mac_version'] = '$VERSION'
with open(path, 'w', encoding='utf-8', newline='\\n') as f: json.dump(data, f)
"

ftp_upload_dir "$DIST_DIR" "$MAC_DIST_SLUG"

if [ -f ".env" ] && grep -q '^WP_APP_POST_ID=' .env 2>/dev/null; then
    echo ""
    echo "📄 紹介ページの Mac ダウンロード設定を同期中..."
    # shellcheck disable=SC1091
    [ -f "$HOME/.wp-env" ] && source "$HOME/.wp-env"
    # shellcheck disable=SC1091
    source .env
    if [ -n "${WP_APP_POST_ID:-}" ] && [ -n "${WP_USER:-}" ] && [ -n "${WP_APP_PASSWORD:-}" ] && [ -n "${WP_SITE_URL:-}" ] && [ -n "${WP_APP_POST_TYPE:-}" ]; then
        curl -s -X POST -u "$WP_USER:$WP_APP_PASSWORD" \
            -H "Content-Type: application/json" \
            -d '{"acf":{"app-macpkg":"dmg","app-macdesc":"macOS 10.15+, DMG<br>日本語,English,中文"}}' \
            "$WP_SITE_URL/wp-json/wp/v2/$WP_APP_POST_TYPE/$WP_APP_POST_ID" >/dev/null \
            && echo "  ✓ app-macpkg=dmg, app-macdesc を更新" \
            || echo "  ⚠️  紹介ページ ACF の更新に失敗"
    fi
fi

if ! $NO_VERUP; then
    echo ""
    echo "📝 次回用バージョンを更新しています..."
    version_save_next "$VERSION"
fi

git_commit_build "$VERSION" "$COMMIT_MSG"

echo ""
echo "🎉 ${APP_NAME} v${VERSION} — ビルド・公証・配布完了!"
echo "📁 $DIST_DIR/$DMG_NAME"
