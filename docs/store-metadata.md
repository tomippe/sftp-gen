# Microsoft Store 申請用メタデータ — SFTP Generator

Partner Center で入力する文言を 3 言語分まとめる。コピペ用のため引用符・表罫線は使わず、見出しの直下に本文のみ置く。

---

## 基本情報

プライバシーポリシー URL

https://apps.tomippe.jp/sftp-gen/policy/

カテゴリ

Developer tools / Productivity

著作権

Copyright © 2026 Studio Tomippe. All rights reserved.

データ収集（個人データ）

いいえ（収集しない。接続情報はユーザーが指定したローカルフォルダ内の sftp.json にのみ保存）

---

## Product identity（manifest / package.json appx と一致させる）

正本: ルート `package.json` の `build.appx` セクション

Package/Identity/Name

StudioTomippe.SFTPGenerator

Package/Identity/Publisher

CN=7AA9757D-D72F-4DE2-9980-F9A659207C27

Package/Properties/DisplayName

SFTP Generator

Package/Properties/PublisherDisplayName

Studio Tomippe

Store URL

https://apps.microsoft.com/detail/9NVBFLCQ74N4?hl=ja-JP&gl=JP

Store ID

9NVBFLCQ74N4（`.env` の `MS_STORE_PRODUCT_ID`）

Identity Version の第 4 桁は常に 0（例: windows/version.txt が 1.3.0 なら 1.3.0.0）

提出パッケージ

windows/build/signed/SFTPGenerator.appxbundle

Partner Center リスト CSV（generate-listing-csv.py 生成）

windows/build/signed/listingData-*.csv

---

## Restricted capabilities（Partner Center 申告）

| 種別 | 名前 | 申告 |
|---|---|---|
| Restricted | runFullTrust | 要 |
| 通常 | internetClient | 申告不要（オプション更新チェック等にのみ使用する場合） |

### runFullTrust — 理由（英語・コピペ用）

SFTP Generator is a full-trust Win32 Electron desktop app. It must read and write sftp.json in the user-chosen project folder, open a folder picker, optionally launch VS Code or Cursor with that folder, and register optional .ste (Dreamweaver site) file handling. These operations are not available to sandboxed Store apps.

---

## 日本語

アプリ名

SFTP Generator

短い説明

Dreamweaver の .ste や手入力から VS Code / Cursor 用 sftp.json を生成。保存時アップロード設定も

説明文

VS Code や Cursor で SFTP 拡張を使うとき、設定ファイル sftp.json の作成は地味に手間がかかります。SFTP Generator は、Adobe Dreamweaver のサイト定義ファイル（.ste）を読み込むか、ホスト名・ユーザー名・パスワード・リモートパス・ローカルフォルダを入力するだけで、プロジェクト用の sftp.json を生成します。

.ste ファイルをダブルクリックして起動することもできます。生成後は VS Code または Cursor でそのフォルダを開く操作を案内します。「ファイル保存時に自動でアップロード」に対応する uploadOnSave オプションもワンクリックで反映できます。

接続情報はあなたの PC 上のプロジェクトフォルダに保存され、開発者のサーバーへ送信されることはありません。日本語・English・简体中文に対応したシンプルなウィンドウ UI です。

What's new in this version

Microsoft Store（Windows）版を公開しました。Dreamweaver .ste のインポート、VS Code / Cursor 向け sftp.json 生成、保存時アップロード設定に対応しています。

Product features

.ste（Dreamweaver サイト定義）のインポート
ホスト・ユーザー・パスワード・リモートパス・ローカルフォルダから sftp.json を生成
uploadOnSave（保存時アップロード）の設定
生成後に VS Code / Cursor でフォルダを開く
.ste ファイルの関連付け（ダブルクリックで起動）
日本語 / English / 简体中文

---

## English

Product name

SFTP Generator

Short description

Build sftp.json for VS Code or Cursor from Dreamweaver .ste or manual fields—including upload on save

Description

Setting up SFTP for VS Code or Cursor means writing sftp.json by hand—easy to get wrong and tedious. SFTP Generator reads Adobe Dreamweaver site definition files (.ste) or lets you enter hostname, username, password, remote path, and local site folder, then writes sftp.json into your project.

You can also double-click a .ste file to open the app with that site loaded. After generation, the app guides you to open the folder in VS Code or Cursor. Optional uploadOnSave is included in one click.

Credentials stay in your project folder on your PC; nothing is sent to the developer’s servers. Simple window UI in Japanese, English, and Simplified Chinese.

What's new in this version

Initial Microsoft Store (Windows) release with .ste import, sftp.json generation for VS Code/Cursor, and upload-on-save support.

Product features

Import Dreamweaver .ste site definitions
Generate sftp.json from host, user, password, paths, and local folder
Optional uploadOnSave in generated config
Open folder in VS Code or Cursor after generation
.ste file association (double-click to launch)
Japanese / English / Simplified Chinese

---

## 简体中文

产品名称

SFTP Generator

简短说明

从 Dreamweaver .ste 或手动输入生成 VS Code / Cursor 的 sftp.json，含保存时上传选项

说明

在 VS Code 或 Cursor 中使用 SFTP 扩展时，手写 sftp.json 既繁琐又容易出错。SFTP Generator 可读取 Adobe Dreamweaver 站点定义文件（.ste），或让你输入主机名、用户名、密码、远程路径与本地站点文件夹，然后在项目中生成 sftp.json。

也可双击 .ste 文件启动并载入站点。生成后会引导用 VS Code 或 Cursor 打开该文件夹。可选的 uploadOnSave 一键写入配置。

连接信息仅保存在你电脑上的项目文件夹中，不会发送到开发者服务器。界面支持日语、英语和简体中文。

此版本的新增内容

首次发布 Microsoft Store（Windows）版，支持 .ste 导入、为 VS Code/Cursor 生成 sftp.json 及保存时上传设置。

产品功能

导入 Dreamweaver .ste 站点定义
根据主机、用户、密码、路径与本地文件夹生成 sftp.json
可选 uploadOnSave
生成后用 VS Code / Cursor 打开文件夹
.ste 文件关联（双击启动）
日语 / 英语 / 简体中文

---

## Notes for Certification（英語のみ）

SFTP Generator is a full-trust Win32 Electron desktop app (APPX). No login or account is required.

1. Install and launch SFTP Generator from the Microsoft Store.
2. Enter hostname, username, password (paste manually), optional remote path, and choose a local site folder with Select.
3. Tap Generate Config File. Confirm sftp.json appears in the chosen folder with expected host/user/remotePath fields.
4. Optional: enable Upload automatically when file is saved and regenerate; confirm uploadOnSave is true in sftp.json.
5. Optional: double-click a sample .ste file in File Explorer; the app should open with fields populated from the file.
6. If VS Code or Cursor is installed, follow the prompt to open the project folder after generation.

The app stores SFTP settings only in the user-selected local project directory. It does not collect personal data or upload credentials to Studio Tomippe servers. Optional update checks may use the network (internetClient).

Privacy policy: https://apps.tomippe.jp/sftp-gen/policy/

---

## 申請前チェックリスト

- [ ] Partner Center で Package Identity Name `StudioTomippe.SFTPGenerator` を予約済み
- [x] `.env` に MS_STORE_PRODUCT_ID を設定（9NVBFLCQ74N4）
- [ ] windows/version.txt / APPX Identity Version（X.Y.Z.0）一致
- [ ] `windows/build/signed/SFTPGenerator.appxbundle` を提出
- [ ] `windows/build/signed/listingData-*.csv` または本ファイルの文言を Partner Center に反映
- [x] プライバシーポリシー URL を Partner Center と apps.tomippe.jp に設定
- [ ] Store 承認後: 紹介ページを Store ボタンへ（app-winurl / app-windesc）＋ FTP の `sftp-gen_win.zip` を削除
- [ ] runFullTrust を申告（理由は上記英語文）
- [ ] .ste ダブルクリック動作を実機確認
