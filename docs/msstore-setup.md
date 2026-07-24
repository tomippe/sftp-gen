# Microsoft Store — SFTP Generator（Windows）

## ビルド

```powershell
cd Y:\Cursor\sftp-gen
.\windows\build-store.ps1
```

提出物: [dist/signed/SFTPGenerator.appxbundle](file:///Y:/Cursor/sftp-gen/dist/signed/SFTPGenerator.appxbundle)

Win 用アイコン・APPX タイルは **`windows/resources/`**（Mac 用 `mac/` は使いません）。

Win 版番号の正本: **`windows/version.txt`**（Mac ルート `version.txt` とは別）

ポータブル EXE（`build.ps1`）:

dist/win-unpacked/SFTP Generator.exe

Store ビルド後の EXE コピー:

windows/publish/SFTP Generator.exe

Partner Center へのパッケージアップロードは手動。掲載文言の正本は [docs/store-metadata.md](store-metadata.md)。

## 初回セットアップ

1. Partner Center で Win32 アプリを作成し、Package identity name を `StudioTomippe.SFTPGenerator` に合わせる（`windows/electron-builder.yml`）。
2. プロジェクト `.env` に Store ID 等を追記（雛形: `docs/msstore-env-snippet.example`）。
3. `%USERPROFILE%\.msstore-env` に署名 PFX パス（`build-common/msstore-env.example` 参照）。POUCHES と同じ Partner Center 証明書を共有可能。

## 参照

- POUCHES: `pouches/native/windows/`（Electron APPX + 署名フロー）
- 共通: `build-common/microsoft-store-setup.md`
