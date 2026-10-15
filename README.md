# eapaka-pocset

[![E2E](https://github.com/oyaguma3/eapaka-pocset/actions/workflows/e2e.yml/badge.svg)](https://github.com/oyaguma3/eapaka-pocset/actions/workflows/e2e.yml)

EAP-AKA の RADIUS 認証の PoC 環境を構成する 4 つのソフトウェアを、組み合わせを確かめた **PoC セット**として提供するためのリポジトリ。各リポジトリに同じ名前のタグ（例 `pocset-v1.0.0`）を付け、その組み合わせと確かめたことを、ここに記録する。

- 状態: 準備中（最初のタグの前）。品質と安定性の改善を進めている（計画書 `docs/plan.md`）。
- 個人の検証用のサンプルであり、商用の運用を想定したものではない。

## PoC セットを構成するもの

| ノード | リポジトリ | 役割 |
|---|---|---|
| RADIUS サーバー（本PoC） | [eapaka-radius-server-poc](https://github.com/oyaguma3/eapaka-radius-server-poc) | EAP-AKA / EAP-AKA' の RADIUS 認証・アカウンティング。認証ベクターの取得、加入者と認可ポリシーの管理（Provisioning API） |
| 認証ベクターのサーバー | [aka-only-server](https://github.com/oyaguma3/aka-only-server) | 加入者の鍵を持ち、認証ベクターを払い出す（本PoC の vector-gateway から使う） |
| provisioner | [eapaka-node-provisioner](https://github.com/oyaguma3/eapaka-node-provisioner) | 上の 2 つの加入者・認可ポリシー・RADIUSクライアントを、1 つの API でまとめて操作する |
| OSS/BSS のサンプル | [eapaka-ossbss-sample](https://github.com/oyaguma3/eapaka-ossbss-sample) | provisioner の管理クライアント。テナントと役割に基づく権限で操作する画面（Cloudflare Access で認証） |

```
[OSS/BSS のサンプル] ──mTLS──> [provisioner] ──mTLS──> [本PoC の Provisioning API]
                                             └─mTLS──> [aka-only-server の管理 API]
[NAS / AP] ──RADIUS──> [本PoC] ──(vector-gateway)──mTLS──> [aka-only-server の認証ベクター API]
```

試験には [eapaka_test](https://github.com/oyaguma3/eapaka_test)（EAP-AKA の試験用のクライアント）を使う。PoC セットには含めず、使ったコミットを記録する。

## 1 台に導入する

4 つを同じホストに置く場合の流れ。手順そのものは各リポジトリの文書にある（ここには写さない）。組み合わせは [`versions.env`](versions.env) のコミット（タグを付けた後はそのタグ）を使う。[`scripts/e2e.sh`](scripts/e2e.sh) が同じ流れを自動で行うので、迷ったときの手本にもなる。

| 順 | ノード | すること | 文書 |
|---|---|---|---|
| 1 | provisioner | イメージをビルドし、下流に提示するクライアント証明書を作る（`gen-client-cert`） | [eapaka-node-provisioner の運用ガイド](https://github.com/oyaguma3/eapaka-node-provisioner/blob/main/docs/operation-guide.md) 2.1・2.2 |
| 2 | aka-only-server | provisioner を管理クライアントに登録して起動する。本PoC の vector-gateway の AVクライアントを登録し、AV用・管理API 用のサーバー証明書を取り出す | [aka-only-server の運用ガイド](https://github.com/oyaguma3/aka-only-server/blob/main/docs/operation-guide.md) 3・4 章、provisioner の運用ガイド 2.3 |
| 3 | 本PoC | aka-only-server への接続（PLMN マップ、AVクライアントの証明書）と Provisioning API（サーバー証明書、provisioner の登録）を設定し、`--profile provisioning` で起動する | [本PoC の docs](https://github.com/oyaguma3/eapaka-radius-server-poc/tree/main/docs) の B-02 アプリケーションデプロイ手順書 §14・§15、provisioner の運用ガイド 2.4 |
| 4 | provisioner | 下流のサーバー証明書を置き、管理クライアント・PLMN マップ・AVクライアントID を設定して起動する。`check-downstream` で確かめる。管理クライアント（`PROVISIONER_ADMIN_CLIENTS`）が 1 つもないと起動しないので、先に OSS/BSS のサンプルの取得とクライアント証明書の作成（その運用ガイド 2.3、2.5 の前半）を済ませる | provisioner の運用ガイド 2.5〜2.8 |
| 5 | OSS/BSS のサンプル | Cloudflare Access / Tunnel を準備し、provisioner と証明書をやり取りして起動する | [eapaka-ossbss-sample の運用ガイド](https://github.com/oyaguma3/eapaka-ossbss-sample/blob/main/docs/operation-guide.md) 2 章 |

ノードの間でそろえる値:

| 値 | 作るところ | 設定するところ |
|---|---|---|
| PLMN マップ（鍵を aka-only-server に置く PLMN） | — | 本PoC の `VECTOR_GATEWAY_PLMN_MAP` と provisioner の `PROVISIONER_PLMN_MAP`（同じ値） |
| provisioner のクライアント証明書のフィンガープリント | provisioner の `gen-client-cert` | 本PoC の `PROVISIONING_API_ADMIN_CLIENTS`、aka-only-server の `AKA_ADMIN_CLIENTS` |
| vector-gateway の AVクライアント | aka-only-server の `client gen-cert` / `client add` | 本PoC の `deployments/certs/av-client.pem`、provisioner の `PROVISIONER_AKA_AV_CLIENT_ID`（その ID） |
| aka-only-server のサーバー証明書 | `av-cert`（AV用）、`admin-cert`（管理API 用） | 本PoC の `deployments/certs/av-server.pem`、provisioner の `certs/aka-server.pem` |
| provisioning-api のサーバー証明書 | 本PoC の手順（openssl。SAN に `DNS:provisioning-api`） | provisioner の `certs/prov-server.pem` |
| OSS/BSS のクライアント証明書のフィンガープリント | `eapaka-ossbss gen-client-cert` | provisioner の `PROVISIONER_ADMIN_CLIENTS` |
| provisioner のサーバー証明書 | provisioner の `server-cert` | OSS/BSS のサンプルの `certs/` |

同じホストでは、compose が作る共有の Docker ネットワーク（`aka-av`、`eapaka-prov`、`eapaka-provisioner`）でつなぐ。ホストに公開する既定のポート:

| ノード | ポート | 既定の公開先 |
|---|---|---|
| 本PoC | RADIUS 1812/udp・1813/udp | すべてのアドレス（NAS から受けるため） |
| 本PoC | Provisioning API 9444、Valkey 6379、Fluent Bit 24224 | 127.0.0.1 |
| aka-only-server | 認証ベクターAPI 8443 | すべてのアドレス（同じホストの本PoC だけが使うなら 127.0.0.1 にできる） |
| aka-only-server | 管理API 9443（平文の 8080 は既定で無効） | 127.0.0.1 |
| provisioner | API 9446 | 127.0.0.1 |
| OSS/BSS のサンプル | なし（Cloudflare Tunnel が外向きに接続する） | — |

## 組み合わせと試験

- 組み合わせの正本は [`versions.env`](versions.env)（各リポジトリのコミット）。
- [`scripts/e2e.sh`](scripts/e2e.sh) が、その組み合わせを 1 台のホストに compose で導入し（各リポジトリの運用ガイドの手順どおり）、eapaka_test で認証の流れ（鍵の置き場所 2 種 × EAP-AKA / EAP-AKA'、拒否、停止・再開、トレースID、OSS/BSS のサンプルからの操作、Valkey の再起動）を確かめる。GitHub Actions（push、PR、毎週月曜）で動くほか、Docker・git・curl・openssl・python3・sudo があれば手元でも動く（`scripts/e2e.sh [作業ディレクトリ]`。待ち受けはすべてループバック）。
- [`scripts/check-pins.sh`](scripts/check-pins.sh) が、provisioner と OSS/BSS のサンプルの CI が契約テストの相手として固定しているコミットと `versions.env` が一致するかを確かめる。

## タグ

- PoC セットのタグは、4 つのリポジトリに同じ名前で付ける注釈つきのタグ（`pocset-vX.Y.Z`）。このリポジトリにも同じタグを付ける。
- 公開したタグは付け替えない。直すことがあれば新しいタグを付ける。
- 各リポジトリの API の版（例 Provisioning API 0.4.0）は、それぞれのリポジトリの流儀のまま。

## ライセンス

MIT（`LICENSE`）。各リポジトリのライセンスは、それぞれのリポジトリを参照。
