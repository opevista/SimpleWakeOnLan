# SimpleWakeOnLan

**SimpleWakeOnLan** は、SwiftUI で開発された macOS 向けの Wake on LAN（WoL）ユーティリティです。  
複数のデバイスを登録・管理し、ワンクリックで起動信号を送信できます。  
また、Ping によるオンライン状態の確認にも対応しています。

---

## 特徴

- 複数デバイスの登録・編集・削除  
- Wake on LAN（Magic Packet）送信  
- Ping によるデバイスのオンライン／オフライン判定  
- 通信ログの自動記録  
- SwiftUI によるモダンな UI  
- macOS のマテリアルを利用した Glass Effect デザイン  
- デバイス情報の自動保存（UserDefaults）

---

## 動作環境

- macOS 12.0 以降  
- Xcode 15 以降（ソースビルド時）  
- Swift 5.9 以降

---

## 使用技術・ライブラリ

- Swift / SwiftUI  
- Network.framework（UDP 通信）  
- SwiftyPing（Ping 実装）

---

## インストール

### GitHub Releases からインストール（推奨）

1. 本リポジトリの **Releases** ページを開きます  
2. 最新バージョンのリリースから `.dmg` をダウンロード  
3. アプリケーションを `/Applications` フォルダへ移動して起動

※ 初回起動時に macOS のセキュリティ警告が表示される場合があります。  
その場合は「システム設定 → プライバシーとセキュリティ」から実行を許可してください。

---

### ソースコードからビルド

```bash
git clone https://github.com/opevista/SimpleWakeOnLan.git
cd SimpleWakeOnLan
open SimpleWakeOnLan.xcodeproj
```

Xcode で実行対象を macOS に設定し、ビルド・実行してください。

---

## 使い方

### デバイスの追加

1. 左上の **＋** ボタンをクリック  
2. 以下の情報を入力  
   - **Name**：デバイス名  
   - **IP Address**：対象デバイスの IP アドレス  
   - **MAC Address**：`AA:BB:CC:DD:EE:FF` 形式  
   - **Broadcast Address**：通常は `255.255.255.255`  
   - **WoL Port**：通常は `9`  
3. **Save** をクリックして登録

---

### Wake on LAN の送信

- デバイス詳細画面の **Wake** ボタンを押すことで、Magic Packet を送信します。

---

### ステータス確認

- **Check Status** を押すと Ping を送信し、デバイスの状態を確認します。

| 表示 | 状態 |
|----|----|
| 🟢 | Online |
| 🔴 | Offline |
| ⚪ | Unknown |

---

## データ保存について

- 登録したデバイス情報および通信ログは `UserDefaults` に保存されます  
- アプリを終了・再起動しても自動的に復元されます

---

## 今後の予定

- iCloud 同期対応  
- Wake 実行履歴の可視化  
- iOS / iPadOS 対応  
- メニューバーアプリ化

---

## ライセンス

MIT License  
詳細は `LICENSE` ファイルを参照してください。

---

## クレジット

- SwiftyPing  
  https://github.com/samiyr/SwiftyPing
