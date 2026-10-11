# PoC セットの品質改善の計画

- 状態: 初版（2026-10-11）。決定事項（§3）はすべて合意済み。ステップ 1（このリポジトリの土台）を終えた。
- 目的: 4 つのリポジトリ（本PoC、aka-only-server、provisioner、OSS/BSS のサンプル）を 1 組の PoC セットとして提供するため、ソフトウェアの品質と安定性を上げ、組み合わせを確かめたうえで共通のタグを付ける。**アーキテクチャと機能は、なるべく今のままにする。**

## 1. 対象

| 略称 | リポジトリ | 計画の開始時点の main | ブランチの流儀 |
|---|---|---|---|
| 本PoC | `oyaguma3/eapaka-radius-server-poc` | `dbd97f5`（Provisioning API 0.4.0。タグは `v0.1.0`（2026-03-05）だけ） | feature → develop → main。設計書・試験仕様書を改版する |
| aka | `oyaguma3/aka-only-server` | `2a6dcf8`（管理 API 0.2.0、認証ベクター API 0.1.0-draft） | main に直接コミット |
| provisioner | `oyaguma3/eapaka-node-provisioner` | `e96390d`（API 0.3.0） | main に直接コミット |
| OSS/BSS | `oyaguma3/eapaka-ossbss-sample` | `605296b` | main に直接コミット |

- 含めないもの: 既存の BFF（web-gui-for-eapaka-radius）、aka 版 GUI（web-gui-for-aka-only-server）。試験に使う eapaka_test は、使ったコミットを記録するだけ。

## 2. 現状（2026-10-11 の調査）

| | 本PoC | aka | provisioner | OSS/BSS |
|---|---|---|---|---|
| Go | 1.25.5（go.work。1.25 系は 1.27.0 の公開（2026-08-19）でサポートが終わった） | 1.27.1 | 1.27.1 | 1.27.1 |
| テスト | 単体 852 関数（Valkey は miniredis）。結合 117 件（T-03）と E2E 27 件（T-04）は手順書での手動 | 単体と Valkey の結合。compose で起動して認証ベクターを取得するまで CI で通す | 単体、Valkey の結合、下流との契約テスト | 単体、PostgreSQL の結合、契約テスト |
| CI の検査 | build、vet、golangci-lint、`-race` | gofmt、vet、`-race`、Docker のビルド、compose | gofmt、vet、`-race`、Docker のビルド、compose の設定、契約テスト | gofmt、vet、`-race`、Docker のビルド、compose の設定、契約テスト |
| 版の埋め込み | provisioning-api だけ | あり（`AKA_VERSION` は文書にない） | あり | あり |
| イメージの版 | `golang:1.25-bookworm`、`debian:bookworm-slim`、`valkey/valkey:9.0`、fluent-bit `4.2` | `golang:1.27.1`、`valkey/valkey:9` | `golang:1.27.1`、`valkey/valkey:9` | `golang:1.27.1`、`postgres:18`、`cloudflared:2026.9.3` |

- 4 つに共通して、govulncheck、カバレッジの計測、CHANGELOG、セットのタグがない。
- 組み合わせを固定しているのは、provisioner の CI（本PoC と aka のコミット）と OSS/BSS の CI（provisioner・本PoC・aka のコミット）だけ。4 つを通した試験（RADIUS の認証まで）は、検証機（simwifi）での手動の確認だけ。

## 3. 決定事項（2026-10-11）

| # | 事項 | 決定 |
|---|---|---|
| 1 | セットの範囲 | 4 つのリポジトリだけにタグを付ける（§1） |
| 2 | タグの名前 | 4 つとこのリポジトリに、同じ名前の注釈つきタグ `pocset-vX.Y.Z` を付ける。各リポジトリの API の版はそのまま。公開したタグは付け替えない |
| 3 | セットの定義の置き場所 | このリポジトリ（`oyaguma3/eapaka-pocset`）。計画書、組み合わせの表、4 つを通した試験、リリースノートを置く |
| 4 | リリースの基準 | §6 |
| 5 | 本PoC の Go | 上げる（§3 の 9 の版） |
| 6 | 直してよい範囲 | 不具合の修正、堅牢化、CI、文書だけ。API と機能は変えない。ただし aka の認証ベクター API の `X-Trace-ID` の対応は入れる（本PoC の vector-gateway は送っている。1 回の認証を 4 つのログでたどれるようにする） |
| 7 | 版の固定 | イメージ（Dockerfile、compose、CI のサービスコンテナ）はパッチ版まで書く（ダイジェストは使わない）。Actions は GitHub のもの（`actions/*`）はメジャー版のタグ、第三者のもの（golangci-lint-action）はコミットの SHA で固定して版をコメントに書く。Dependabot の更新の PR は使わない（依存はセットのリリースのときにまとめて上げる）。脆弱性は govulncheck で、push のときと週 1 回調べる |
| 8 | イメージの公開 | しない（利用者はタグからソースでビルドする） |
| 9 | Go の版 | 4 つとも Go 1.27.2（2026-10-08 公開。`go` コマンド、`crypto/tls`、`html/template`、`net/http`、`net/textproto`、`os` のセキュリティ修正を含む）。go.mod の `go` の行、Dockerfile の `golang` のイメージ、CI を同じ版にそろえる。セットのリリースの直前に、その時点の最新のパッチ版を確かめる |

## 4. 直す項目

重さ: 高（障害で止まる・気づけない、または安全に関わる）、中（条件によって問題になる）、低（文書・体裁）。ステップ（§5）で、リポジトリごとにまとめて直す。

### 4.1 4 つに共通

| ID | 重さ | 内容 |
|---|---|---|
| C-1 | 高 | Go を 1.27.2 にそろえる（§3 の 9） |
| C-2 | 高 | govulncheck を CI に加える（push のときと週 1 回） |
| C-3 | 中 | イメージの版をパッチ版まで書く（§3 の 7） |
| C-4 | 中 | 第三者の Action を SHA で固定する（本PoC の golangci-lint-action） |
| C-5 | 低 | CHANGELOG を置く（セットのタグの単位で、変わったことを書く） |

### 4.2 本PoC

| ID | 重さ | 内容 |
|---|---|---|
| P-1 | 高 | auth-server・acct-server が、UDP のポートを開けなくても終了しない（ログを出すだけ）。healthcheck は `pgrep` なので healthy のまま。開けなければ終了する |
| P-2 | 高 | auth-server・acct-server の RADIUS の処理に panic の回復がない（1 つのパケットでプロセスが落ちる）。パケットごとに回復してログに出す |
| P-3 | 中 | vector-api・vector-gateway の HTTP サーバーにタイムアウトがない |
| P-4 | 中 | `VALKEY_PASSWORD` が未設定でも compose が起動を続ける（`${VALKEY_PASSWORD:?}` で止める） |
| P-5 | 中 | 版を埋め込むのが provisioning-api だけ。全バイナリに埋め込み、起動のログに出す |
| P-6 | 中 | CI に gofmt の検査、Docker のビルド、`permissions`・`concurrency` を加える（他の 3 つとそろえる） |
| P-7 | 中 | 設定の検証の漏れ（vector-gateway の内部のタイムアウトが正か、vector-api の設定）。使っていない定数（`VectorConnectTimeout`） |
| P-8 | 中 | コンテナが root で動く。nonroot にできるかを確かめる（ログ・ボリュームの権限に影響するので、確かめてから決める） |
| P-9 | 低 | 文書と実装のずれ: T-01（「CI は将来」、ない `tests/integration` への言及、golangci の古い例）、README（テストの件数、`go test ./...`）、古い r 番号での参照、件数の食い違い |
| P-10 | 低 | 公開の文書から、git の管理外の `docs/subdocs/`・`docs/testresults/` を 25 か所参照している。参照を直すか、要るものを管理に入れる |

### 4.3 aka

| ID | 重さ | 内容 |
|---|---|---|
| A-1 | 中 | 認証ベクター API で `X-Trace-ID` を受け取り、ログに残す（§3 の 6。本PoC の D-12 §4.5 の記述も合わせる） |
| A-2 | 中 | 本体のコンテナに healthcheck がない（`healthcheck` のサブコマンドを加える。distroless のため） |
| A-3 | 中 | 停止の猶予（10 秒）が Docker の既定の猶予（10 秒）と同じ。compose の `stop_grace_period` を長くする |
| A-4 | 低 | `AKA_VERSION` を `.env.example` と文書に書く。CI の SKIP の検出に `pipefail` を付ける |

### 4.4 provisioner

| ID | 重さ | 内容 |
|---|---|---|
| V-1 | 中 | やり直しのワーカーに panic の回復がない |
| V-2 | 中 | 停止のときにワーカーの終了を待たない |
| V-3 | 中 | IMSI のロックの TTL（60 秒）と、下流の呼び出しの上限（`PROVISIONER_DOWNSTREAM_TIMEOUT`）×手順の数の大小を、設定の検証で確かめていない |
| V-4 | 中 | 本体のコンテナに healthcheck がない。停止の猶予が Docker の既定と同じ（A-2・A-3 と同じ） |
| V-5 | 低 | README の「Go 1.27 以上」を実際の版に合わせる。下流用のクライアント証明書は再起動しないと読み直さないことを運用ガイドに書く |

### 4.5 OSS/BSS

| ID | 重さ | 内容 |
|---|---|---|
| O-1 | 中 | `postgres:18`、CI の `valkey/valkey:9` をパッチ版まで書く（C-3） |

各リポジトリの直す前の確認で、項目が増えたら、この表に足す。

## 5. ステップ

各ステップの終わりに、作ったものと実際に動かして確かめたことを報告し、確認をもらう。

| # | 内容 | 主な成果 |
|---|---|---|
| 1 | このリポジトリの土台 | README、この計画書、組み合わせの表（§7）の形 |
| 2 | aka・provisioner・OSS/BSS の CI と Go | C-1〜C-3（3 つの分）、A-4、O-1。Go 1.27.2 に上げ、govulncheck を加え、イメージの版を固定する。provisioner と OSS/BSS の CI が固定する相手のコミットを更新する |
| 3 | 本PoC の Go と CI | C-1〜C-4（本PoC の分）、P-6。Go 1.25.5 → 1.27.2（依存は govulncheck の指摘があるものだけ上げる）。本PoC の流儀（feature → develop → main、文書の改版） |
| 4 | 安定性の修正 | P-1〜P-5・P-7・P-8、A-1〜A-3、V-1〜V-5。リポジトリごとに 1 回ずつ |
| 5 | 4 つを通した試験の自動化 | このリポジトリの CI で、4 つ（と eapaka_test）を組み合わせの表のコミットで起動し、加入者の登録 → EAP-AKA の認証で Accept（鍵の置き場所 2 種）→ 停止で Reject → 再開で Accept、を確かめる。細部はこのステップの確認事項で決める |
| 6 | 文書とリリースノート | P-9・P-10、C-5、組み合わせの表、導入の手順（このリポジトリの README から各リポジトリの運用ガイドへの案内） |
| 7 | 最終の確認とタグ | simwifi での通し（Cloudflare を通した OSS/BSS の画面、本PoC の T-03 の必須 23 件）。§6 を満たしたら、5 つのリポジトリにタグを付ける |

## 6. リリースの基準

タグを付ける前に、すべてを満たすこと。

- [ ] 4 つのリポジトリの CI が、タグを付けるコミットで成功している。
- [ ] govulncheck の指摘がない（4 つとも）。
- [ ] 4 つを通した試験（ステップ 5）が、組み合わせの表のコミットで成功している。
- [ ] provisioner と OSS/BSS の CI が固定する相手のコミットが、組み合わせの表と一致している。
- [ ] simwifi での通しの確認が済んでいる（ステップ 7）。
- [ ] 文書（README、運用ガイド、設計書）と実装に食い違いがない。リリースノートを書いた。

## 7. 組み合わせの表（タグを付けるときに埋める）

| リポジトリ | コミット | 版（Go、API など） |
|---|---|---|
| 本PoC | | |
| aka | | |
| provisioner | | |
| OSS/BSS | | |
| eapaka_test（試験用。タグは付けない） | | |

## 8. タグの付け方

1. 組み合わせの表（§7）を埋め、§6 を満たしたことを確かめる。
2. 4 つのリポジトリの、表のコミットに注釈つきタグを付けて push する（`git tag -a pocset-vX.Y.Z <コミット> -m "PoC セット vX.Y.Z"`、`git push origin pocset-vX.Y.Z`）。
3. このリポジトリの、表を記録したコミットに同じタグを付け、GitHub のリリース（リリースノート）を作る。
4. 公開したタグは付け替えない。直すことがあれば、パッチ版を上げた新しいタグにする。
