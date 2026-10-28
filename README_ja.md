[中文](README_zh.md) | [English](README.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Español](README_es.md) | [Français](README_fr.md) | [Deutsch](README_de.md) | [Русский](README_ru.md)

# 蘇瑾言 / サイバー・スチュワード — オープンソース自ホスト構成

> Windows 上で動作する QQ エージェント向けの自ホスト構成です。デュアルアカウント分離、GPU/VRAM スケジューリング、高危険操作 Broker、TOTP 認証、ファイル送信制御、日次監査を備えます。

> **本プロジェクトは Tencent、QQ、AstrBot、SnowLuma の公式プロジェクトではなく、いかなる提携・承認・後援関係もありません。**

## ⚠️ 免責事項および法的リスク（必ずお読みください）

1. **非公式プロトコルに伴うリスク**：本プロジェクトは、SnowLuma 等の第三者が提供する**非公式** QQ プロトコルクライアントに依存しています。当該利用は Tencent の「QQ ソフトウェア使用許諾契約およびサービス契約」に違反する可能性があり、アカウントの制限、停止、**永久凍結**を招くおそれがあります。利用者は、アカウント喪失やデータ損失を含む**すべての結果を自ら負担**するものとします。
2. **責任の免除**：本プロジェクトは、個人の学習、研究、およびローカル環境でのセキュリティ技術交流のみを目的として提供されます。商業利用、不法な利益追求、ブラックマーケット活動、悪意ある破壊行為を固く禁止します。適用法令の許容する最大限の範囲において、開発者および貢献者は、本プロジェクトの利用、誤用、利用不能に起因する直接的・間接的・偶発的・特別・結果的損害、および**連帯責任**を含む一切の責任を負いません。これには、法的紛争、刑事責任、データ損失、経済的損失が含まれます。
3. **AGPL-3.0 コンプライアンス**：本プロジェクトには AstrBot に基づく Overlay の改変コードが含まれ、**AGPL-3.0** の下で提供されます。AGPL-3.0 のソースコード提供義務を含む条件を遵守してください。**クローズドソースでの商業利用は禁止**です。
4. **無保証**：本ソフトウェアは「現状のまま（AS IS）」提供され、明示・黙示を問わずいかなる保証も行いません。実アカウント接続前に、隔離されたテスト環境で権限を確認してください。

## アーキテクチャ

```mermaid
flowchart LR
    QQ["QQ / Tencent protocol"] --> SL["SnowLuma<br/>desktop user session"]
    SL --> AB["AstrBot<br/>low-privilege service account"]
    AB --> LLM["模型路由<br/>local Ollama / API"]
    AB --> ACL["共享目录 ACL<br/>read + create only"]
    AB -->|"127.0.0.1:18090<br/>broker token"| BR["SYSTEM Broker"]
    BR -->|"TOTP challenge"| PHONE["手机 Authenticator"]
    PHONE -->|"6 位动态码"| BR
    BR -->|"delete / overwrite<br/>quarantine + backup"| FS["受保护文件区"]
    AB -. "ACL deny" .-> VAULT["TOTP 保险箱<br/>仅 YOUR_USER_NAME/管理员"]
    BR -->|"仅回环访问"| LOCAL["本机管理端"]
```

### ACL 防護境界

- AstrBot サービスアカウントは TOTP 保管庫を**読み取れません**。
- 共有フォルダは新規作成と読み取りのみ許可し、既存ファイルの削除・上書きを拒否します。
- 削除・上書きは、TOTP 承認後に SYSTEM Broker のみが実行します。
- ファイル送信時は、パス、機密語、圧縮ファイル、一括件数/容量、ファイル所有者も検査します。
- Broker と AstrBot Dashboard は**ループバック接続のみ**受け付けます。

## 主な特徴

### 1. デュアルアカウント分離

- AstrBot は専用の低権限サービスアカウント（`YOUR_SERVICE_USER`）で動作します。
- QQ/SnowLuma のデスクトップセッションと AstrBot サービスアカウントを分離します。
- AstrBot は機密ディレクトリに対する読み取り・削除・上書き権限を持ちません。
- 破壊的なファイル操作は SYSTEM Broker に委任し、スマートフォンの TOTP を必須とします。

### 2. GPU / VRAM スケジューリング

- ローカル Ollama モデルを必要時に読み込み、アイドル時に解放します。
- ゲーム起動時は API プロバイダーへ切り替え、ローカル VRAM を解放します。
- ゲーム終了時にローカルモデルを再読み込みします。
- ランチャー/子プロセス検出と GPU 使用率検出を併用します。

### 3. 高危険操作 Broker

- ネイティブ AstrBot ツールは危険なファイル操作を直接実行しません。
- ローカル HTTP（ループバック限定）とトークンで Broker に要求します。
- Broker は QQ 経由でワンタイム TOTP チャレンジを送信します。
- 削除は隔離領域へ移動し、上書きは旧版をバックアップします。
- すべての操作を監査 JSONL に記録します。

### 4. ファイル送信の段階的制御

- ホワイトリストディレクトリ + 非機密ファイル名 + 信頼できる所有者 → 直接送信。
- 機密名、外部パス、圧縮ファイル、URL、一括件数/容量超過 → TOTP。
- AI が外部ファイルをホワイトリストへコピーして送信する迂回を、所有者検査で防止します。

### 5. プロンプトインジェクション門番

- オーナーの QQ は完全に信頼します。
- 他の QQ ユーザーが典型的なインジェクション/権限昇格パターンに一致した場合、モデル投入前に遮断し記録します。

### 6. 日次監査とブリーフィング

- 日次監査：ファイル数、ツール呼び出し、コード実行、権限拒否。
- 日次ブリーフィング：設定可能な IT ニュースと GitHub Trending の要約。
- 任意の `/lockapi` / `/unlockapi` 手動制御。

## ハードウェア要件

| GPU / VRAM | 推奨ローカルモデル | 体験 | プロファイル |
|---|---|---|---|
| RTX 4090 / 24GB+ | 20B–24B、24k コンテキスト | ローカル会話・音声・記憶が完全。ゲーム時は自動解放 | `config.pro.example.json` |
| 16GB（4080/4070Ti 級） | 7B–14B、8k–16k | ローカル利用可。複雑なタスクは API 推奨 | `config.pro.example.json`、モデルを縮小 |
| 8GB（3060Ti/4060 級） | 3B–7B 量子化、4k–8k | 基本的なローカル会話。長文/ツールは API 推奨 | `config.pro.example.json`、モデルを縮小 |
| 単体 GPU なし / AMD 内蔵 GPU / 8GB 未満 | ローカルなし | **API 専用モード。分離機能はすべて利用可能** | `config.lite.example.json` |
| NVIDIA なし、Ollama の CPU 実行 | CPU 推論 | 非常に遅い。常時会話には非推奨 | 利用可能だが lite 推奨 |

> VRAM は Q4 量子化、24k コンテキスト、単一モデル常駐を前提とした目安です。実際の要件はモデルカードと Ollama に依存します。

**RTX 4090 も Ollama も不要な lite モードがあります。** `astrbot_plugin_cloud_fallback` がポート `11434` を検出し、ローカルモデルが使えない場合は会話を DeepSeek に切り替え、次の警告を記録します。

```text
未检测到本地模型，已自动切换为纯云端模式
```

### Lite / API 専用モード

1. Ollama をインストールしない。GPU 不要。
2. AstrBot に DeepSeek API キーを設定。
3. `config.lite.example.json` をデプロイプロファイルとして使用。
4. セキュリティ Overlay、プラグイン、Broker をコピー。
5. ACL、Broker、TOTP、ファイル送信制御、監査はすべて有効。
6. ゲームモードはローカルモデルの解放/再読込をスキップし、`Skipped (Ollama not found)` と記録。

## 前提条件

各依存関係をインストールし、ライセンスを確認してください。

- Windows 10/11
- Python 3.10+
- [AstrBot](https://github.com/AstrBotDevs/AstrBot) v4.29.x
- SnowLuma（非公式 QQ プロトコルアダプター。ライセンス遵守）
- Ollama（任意。ローカルモデル用）
- Node.js（Playwright MCP、SnowLuma）
- LibreHardwareMonitor（任意）

本リポジトリには AstrBot、SnowLuma、モデル重み、QQ クライアント、第三者ランタイムデータは**含まれません**。

## インストール概要

1. AstrBot / SnowLuma / Ollama（任意）をインストール。
2. 対象の AstrBot ディレクトリをバックアップ。
3. `overlay/astrbot/` 配下のファイルを対応する AstrBot パスへコピー：
   - `overlay/astrbot/core/tools/message_tools.py`
   - `overlay/astrbot/core/tools/web_search_tools.py`
   - `overlay/astrbot/dashboard/server.py`
4. `plugins/` 配下のカスタムプラグインを AstrBot の `data/plugins/` へコピー。
5. すべての `YOUR_*` プレースホルダーを自分の値に置換。
6. `docs/使用説明.md`（中国語の導入ガイド）に従い、アカウント、パス、タスク、TOTP を設定。
7. 実際の QQ アカウントを接続する前に、権限、Broker、監査をテスト環境で検証。

### AstrBot Overlay に関する注意

`overlay/` は AstrBot v4.29.3 向けのローカルセキュリティパッチであり、AstrBot の完全なソースではありません。アップグレード後は次を再確認・再適用してください。

- `message_tools.py` のファイル送信 TOTP ガード；
- `web_search_tools.py` の `$ENV` キー解決；
- `dashboard/server.py` の loopback-only ミドルウェア。

### ポート

- AstrBot dashboard/API：`127.0.0.1:6185`
- TOTP Broker：`127.0.0.1:18090`
- 両サービスはループバックのみ受け付けます。Broker は `127.0.0.1`/`::1` 以外を明示的に拒否します。

## プレースホルダー

| プレースホルダー | 意味 |
|---|---|
| `YOUR_QQ_ID` | オーナーの QQ 番号 |
| `YOUR_USER_PATH` | デスクトップユーザーのプロファイルパス |
| `YOUR_SERVICE_PATH` | AstrBot サービスアカウントのプロファイルパス |
| `YOUR_SERVICE_USER` | AstrBot 実行アカウント |
| `YOUR_USER_NAME` | デスクトップユーザー名 |
| `YOUR_HOST` | ホスト名 |
| `YOUR_PROJECT_PATH` | プロジェクトのインストールパス |

`YOUR_` を検索し、デプロイ前にすべて置換してください。

## セキュリティ境界

対応済み：

- 削除/上書き：ACL + Broker + TOTP。
- 高危険ファイル送信：パス/機密名/圧縮/一括ポリシー + TOTP。
- 他の QQ ユーザーからのプロンプトインジェクション：モデル前段の門番。
- ネットワーク露出：Broker と AstrBot dashboard の loopback 制限。

未対応：

- 画像・音声・動画送信の同等 TOTP。
- Shell 実行の同等 TOTP。
- Windows の物理確認ダイアログ。
- サードパーティプラグイン自体のすべての副作用。

## ライセンス

本リポジトリは **GNU Affero General Public License v3.0（AGPL-3.0）** で提供されます。`LICENSE` を参照してください。

`overlay/` には AstrBot（AGPL-3.0）に基づく改変ファイルが含まれます。本リポジトリまたは改変版を配布する場合は、ソースコード提供義務を含む AGPL-3.0 を遵守してください。

AstrBot、SnowLuma、Ollama などの依存プロジェクトは各作者に帰属します。利用前に各ライセンスを確認してください。
