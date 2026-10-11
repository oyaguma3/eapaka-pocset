# eapaka-pocset

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

## タグ

- PoC セットのタグは、4 つのリポジトリに同じ名前で付ける注釈つきのタグ（`pocset-vX.Y.Z`）。このリポジトリにも同じタグを付ける。
- 公開したタグは付け替えない。直すことがあれば新しいタグを付ける。
- 各リポジトリの API の版（例 Provisioning API 0.4.0）は、それぞれのリポジトリの流儀のまま。

## ライセンス

MIT（`LICENSE`）。各リポジトリのライセンスは、それぞれのリポジトリを参照。
