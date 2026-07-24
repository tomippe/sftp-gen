# Partner Center 提出用（ビルド成果物のコピー）

`windows/build-store.ps1` 実行後に `dist/` からコピーされます。

- SFTPGenerator.appxbundle — Partner Center にアップロード
- SFTP Generator.exe — Store / ポータブルビルドの x64 EXE（`dist/win-unpacked/` のコピー）
- listingData.csv — Store listings インポート用（正本は ../docs/store-metadata.md）

再ビルドで上書きされます。
