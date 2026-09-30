# SFTP Generator 紹介ページ設定

## 公開ステータス

**公開済み**（`status: publish`）。

## URL

- 紹介ページ: https://apps.tomippe.jp/sftp-gen/
- プライバシーポリシー: https://apps.tomippe.jp/sftp-gen/policy/

## WordPress 投稿 ID

| 用途 | ID |
|------|-----|
| 紹介ページ（app） | **1662** |
| プライバシーポリシー（app / 子ページ） | **2423** |

## キャッチフレーズ（app-cp）

VSCodeのSFTPプラグイン設定ツール
FTP接続を気軽に始められます

## プラットフォーム

- **platform**: ["mac", "win"]
- **app-macpkg**: **dmg**（直接配布のリンク先 `{slug}_mac.dmg`。未設定時は zip）
- **app-macdesc**: `macOS 10.15+, DMG<br>日本語,English,中文`
- **app-windesc**: `Windows 10+, vX.Y.Z, ZIP<br>日本語,English,中文`（現状 ZIP。Store 承認後に切替）
- **app-winurl**: 空（ZIP）。Store 承認後: `https://apps.microsoft.com/detail/9NVBFLCQ74N4?hl=ja-JP&gl=JP`

Mac ダウンロードボタンの URL は WordPress の **app-macpkg** と FTP 上の `manifest.json`（`mac_version`）から組み立てられる。DMG 配布に切り替えたら **app-macpkg を dmg に更新**すること（commandk-bar / disk-monitor と同様）。

### Store 承認後にやること（ユーザーから指示があったとき）

1. 紹介ページ: `app-winurl` / `app-windesc` を Store 向けに更新
2. **FTP `apps/sftp-gen/sftp-gen_win.zip` をサーバーから削除**（ZIP 配布をやめる）
3. ローカル `../apps.tomippe.jp/sftp-gen/sftp-gen_win.zip` があれば同様に削除

## 配布ファイル（FTP: apps/sftp-gen/）

| ファイル | 用途 |
|----------|------|
| `sftp-gen_mac.dmg` | Mac 直接配布 |
| `latest-mac.yml` | electron-updater（アプリ内の更新確認） |
| `appcast.xml` | Sparkle 互換フィード（外部ツール用。アプリ本体は electron-updater） |
| `manifest.json` | 紹介ページの版表示・リンク組み立て |
| `sftp-gen_win.zip` | Windows ポータブル（Store 承認までは ZIP。承認後は削除） |

## KV背景・キー色

- **app-keycolor**: #7727bd
- **app-kvbgaddcss**: screen ブレンド

## ローカル連携

- プロジェクト `.env`: `WP_APP_POST_ID`, `WP_APP_PAGE_URL`, `WP_POLICY_POST_ID`, `WP_POLICY_PAGE_URL`
- REST API: `source ~/.wp-env && source .env` のあと curl で ACF 更新

### Mac 配布形式を DMG に変更するとき

```bash
source ~/.wp-env && source .env
curl -s -X POST -u "$WP_USER:$WP_APP_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"acf":{"app-macpkg":"dmg","app-macdesc":"macOS 10.15+, DMG<br>日本語,English,中文"}}' \
  "$WP_SITE_URL/wp-json/wp/v2/$WP_APP_POST_TYPE/$WP_APP_POST_ID"
```
