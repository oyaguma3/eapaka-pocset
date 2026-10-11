# PoC セットの品質改善の計画

- 状態: 初版（2026-10-11）。決定事項（§3）はすべて合意済み。ステップ 1〜4 を終えた（記録は §9）。
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
| 7 | 版の固定 | イメージ（Dockerfile、compose、CI のサービスコンテナ）はパッチ版まで書く（ダイジェストは使わない）。Actions は GitHub のもの（`actions/*`）はメジャー版のタグ、第三者のもの（golangci-lint-action）はコミットの SHA で固定して版をコメントに書く。Dependabot の更新の PR は使わない（依存はセットのリリースのときにまとめて上げる）。脆弱性は govulncheck で、push のときと週 1 回調べる。例外: distroless（`gcr.io/distroless/static-debian13:nonroot`）は版のタグがないのでタグのまま（中身は CA 証明書などの最小限のファイルで、作り直しは修正の取り込み。ステップ 2 の確認事項 5） |
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
| P-8 | 中 | コンテナが root で動く。**見送り**（ステップ 4 の確認事項 8h。nonroot にすると、証明書の鍵の所有者を変える手順が導入済みの環境すべてに要り、手順書も広く直すことになる。待ち受けは特権のいらないポートだけ） |
| P-9 | 低 | 文書と実装のずれ: T-01（「CI は将来」、ない `tests/integration` への言及、golangci の古い例）、README（テストの件数、`go test ./...`）、古い r 番号での参照、件数の食い違い |
| P-10 | 低 | 公開の文書から、git の管理外の `docs/subdocs/`・`docs/testresults/` を 25 か所参照している。参照を直すか、要るものを管理に入れる |
| P-11 | 中 | vector-gateway・vector-api・provisioning-api の停止の上限（10 秒）が Docker の既定の猶予と同じ（ステップ 4 で追加・対応） |
| P-12 | 低 | ステップ 4 で残した文書の記述: T-03（1032 行）・T-04（589 行）の「aka-only-server はトレースID を記録しない」、B-03 §6 のサービスごとのビルドに `POC_VERSION` がない、subdoc の UT-AUTH-CONFIG-010 の `VectorConnectTimeout`（ステップ 6 で直す） |

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
| O-2 | 中 | 停止の上限（10 秒）が Docker の既定の猶予と同じ（ステップ 4 で追加・対応） |

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

## 9. 記録

### 9.1 ステップ 1: このリポジトリの土台（2026-10-11）

README と、この計画書を置いた（`332ec36`）。

### 9.2 ステップ 2: aka・provisioner・OSS/BSS の Go と CI（2026-10-12）

確認事項（2026-10-12 にすべて推奨案で合意）:

| # | 事項 | 決定 |
|---|---|---|
| 1 | govulncheck の入れ方 | `go run golang.org/x/vuln/cmd/govulncheck@v1.9.0 ./...`（Action は使わない。版は固定され、中身は Go のチェックサムのデータベースで照合される） |
| 2 | 実行の場所と頻度 | CI とは別のワークフロー `.github/workflows/govulncheck.yml`。push、pull request、手動、毎週月曜 9 時台（日本時間。cron `23 0 * * 1`） |
| 3 | Valkey の版 | 3 つとも `9.1.2`（それまでの `:9` が指していた版）。本PoC（`9.0`）はステップ 3 で決める |
| 4 | PostgreSQL の版 | `18.6` |
| 5 | distroless | 例外としてタグのまま（§3 の 7） |
| 6 | OSS/BSS の govulncheck の指摘 | `golang.org/x/text` v0.29.0 の GO-2026-6629・GO-2026-5970（pgx から使われる）。x/text を v0.43.0 に上げた（x/sync も v0.24.0 に上がった）。pgx は v5.11.0 が最新 |
| 7 | 固定のコミットの更新 | aka → provisioner → OSS/BSS の順にコミットし、provisioner の `AKA_REF`、OSS/BSS の `AKA_REF`・`PROVISIONER_REF` を更新した |
| 8 | 確かめ方 | 手元（gofmt・vet・`go test -race`（固定したパッチ版のイメージでの結合テスト、スキップなし）・govulncheck・イメージのビルド・compose の設定）と各リポジトリの CI |

| リポジトリ | コミット | 内容 | CI |
|---|---|---|---|
| aka | `b003b11` | Go 1.27.2、Valkey 9.1.2（compose・CI・README・運用ガイド）、govulncheck、`AKA_VERSION` を `.env.example`・README・運用ガイドに（A-4）、CI の結合テストの確認に `pipefail`（A-4） | CI 3 ジョブ（compose での起動から認証ベクターの取得までの通しを含む）と govulncheck が成功 |
| provisioner | `51c9eee` | Go 1.27.2、Valkey 9.1.2、govulncheck、README の「Go 1.27 以上」を 1.27.2 に（V-5 の一部）、`AKA_REF` を `b003b11` に | CI 3 ジョブ（aka `b003b11`・本PoC `dbd97f5` との契約テストを含む）と govulncheck が成功 |
| OSS/BSS | `cb09b64` | Go 1.27.2、x/text v0.43.0、postgres 18.6、CI の Valkey 9.1.2、govulncheck、`PROVISIONER_REF` を `51c9eee`・`AKA_REF` を `b003b11` に（O-1） | CI 3 ジョブ（provisioner `51c9eee`・本PoC `dbd97f5`・aka `b003b11` との契約テストを含む）と govulncheck が成功 |

- 3 つとも、手元の govulncheck（Go 1.27.2）で指摘なし。govulncheck は使っている Go の版で標準ライブラリを判定するので、Go 1.27.1 のままなら 1.27.2 で直った脆弱性が指摘される見込み（1.27.1 では試していない）。
- GitHub Actions の `ubuntu-latest` は 2026-10-19 から Ubuntu 26 に移る予告が出ている（provisioner の CI の注記）。CI が落ちたら、まずそれを疑う。

### 9.3 ステップ 3: 本PoC の Go と CI（2026-10-12）

確認事項（2026-10-12 にすべて推奨案で合意）:

| # | 事項 | 決定 |
|---|---|---|
| 1 | Go と依存 | `go.work` と 7 つの go.mod を Go 1.27.2 に。依存は govulncheck の指摘のものだけ上げる: `golang.org/x/net` v0.46.0 → v0.60.0（GO-2026-6617・6612・6611・6603）、`github.com/quic-go/quic-go` v0.54.0 → v0.59.1（GO-2026-5676、GO-2025-4233）。どちらも gin v1.11.0 から使われる間接依存（gin v1.12.0 でも修正版に届かないので、gin は据え置き）。推移で x/crypto・x/sys・x/text・x/tools なども上がった |
| 2 | イメージ | `golang:1.27.2-bookworm`、`debian:12.15-slim`、`fluent/fluent-bit:4.2.8`、Valkey は他の 3 つとそろえて `9.0` → `9.1.2` |
| 3 | CI | `actions/checkout`・`setup-go` を v7 に、`golangci-lint-action` v9.3.0 を SHA（`ba0d7d2`）で固定、golangci-lint v2.10 → v2.14.0、gofmt の確認、`permissions`・`concurrency`、イメージ 5 つのビルドと compose の設定のジョブ（P-6） |
| 4 | govulncheck | 他の 3 つと同じワークフロー（main・develop への push、PR、手動、毎週月曜）。go.work の直下では動かないので、`make vulncheck` でモジュールごとに実行する |
| 5 | 文書の改版 | 版を書いている文書を改版: B-03(r3)、D-01(r23)、D-02(r26)、D-08(r27)、D-09(r22)、D-10(r15)、D-11(r13)、D-12(r10)、E-01(r9)、E-03(r16)、ドキュメント一覧(r65)、README、CLAUDE.md。T-01 の古い CI の節と、文書どうしの参照の古い版数はステップ 6（P-9）で直す |
| 6 | ブランチと PR | `feature/go-1.27` → develop（#55、squash）→ main（#56、merge commit） |
| 7 | 確かめ方 | 手元、PR と main の CI、simwifi での動作確認 |
| 8 | 他のリポジトリ | provisioner の `POC_REF`、OSS/BSS の `POC_REF`・`PROVISIONER_REF` を更新 |

| リポジトリ | コミット | 内容 | CI |
|---|---|---|---|
| 本PoC | develop `829cf29`（#55）、main `061d7d0`（#56） | 上の 1〜5 | PR・main とも、ビルドとテスト（golangci-lint を含む）、イメージと compose の設定、govulncheck が成功 |
| provisioner | `be26ecb` | `POC_REF` を本PoC `061d7d0` に | CI 3 ジョブ（本PoC `061d7d0`・aka `b003b11` との契約テストを含む）と govulncheck が成功 |
| OSS/BSS | `4a70c40` | `PROVISIONER_REF` を `be26ecb`、`POC_REF` を `061d7d0` に | CI 3 ジョブ（契約テストを含む）と govulncheck が成功 |

手元での確認: Go 1.27.2 で `make build`・`vet`・`test-race`・`lint`（0 issues）、gofmt、`make vulncheck`（7 モジュールとも指摘なし。x/crypto の openpgp の 1 件は呼んでいないので対象外）、イメージ 5 つのビルド（中のバイナリは go1.27.2、Debian 12.15）、compose の設定。

simwifi での確認（2026-10-12。本PoC の `feature/go-1.27` `771738b`、aka `b003b11`、provisioner `51c9eee` を同一ホストに compose で導入。待ち受けはループバック）:

- 本PoC の 7 つのコンテナが起動（fluent-bit 以外は healthy）。Valkey 9.1.2、Fluent Bit 4.2.8、アプリのコンテナは Debian 12.15・go1.27.2。起動ログにエラーなし。provisioner の `check-downstream` で下流 2 つと AVクライアントに接続できた。
- provisioner の API で RADIUSクライアントと加入者 2 人（`440200000000001` は本PoC、`440100000000001` は aka-only-server に鍵）を登録し、eapaka_test で 2 人 × EAP-AKA / EAP-AKA' の 4 通りとも Access-Accept。
- 停止（`PUT /policies/{imsi}/status`）で Reject（auth-server に `AUTH_SUBSCRIBER_SUSPENDED`）、再開で Accept（2 人とも）。provisioner の監査ログに `policy.suspend` / `policy.resume`。
- 本PoC の Valkey を再起動しても、AOF から読み込んでデータが残り（停止の状態も）、4 通りとも Accept。
- Fluent Bit 4.2.8 を通してホストに 7 つのログファイル。/health のログの振り分け（others.log）も動いた。
- 片付け済み（作業前と同じ状態。`~/aka-work/ossbss-dev/tunnel-token` は残した）。

### 9.4 ステップ 4: 安定性の修正（2026-10-12）

確認事項（2026-10-12 にすべて推奨案で合意。8h は見送り。10 は simwifi の確認で見つかった副作用への対応で、案 A で合意）:

| # | 事項 | 決定 |
|---|---|---|
| 1 | A-1 `X-Trace-ID` | 認証ベクターAPI で受け取り（なければ採番し）、払い出しのログに `trace_id`、応答のヘッダーで返す。管理API と同じ作り（共通の部品 `internal/traceid`）。認証ベクターAPI 0.2.0-draft |
| 2 | A-2 healthcheck | サブコマンド `healthcheck`（有効なリスナーに TCP で接続できるか。mTLS のため HTTP までは見ない）。compose の healthcheck、CI の通しの確認は `--wait` |
| 3 | A-3 | `stop_grace_period: 20s` |
| 4 | V-1 / V-2 | ワーカーは操作 1 件ごとにパニックを回復。停止のときは処理中の操作の終わりを最大 15 秒待つ |
| 5 | V-3 | `PROVISIONER_DOWNSTREAM_TIMEOUT` が 10 秒を超えたら起動しない |
| 6 | V-4 / V-5 | healthcheck、`stop_grace_period: 30s`。下流用の証明書の再読み込みの注意は運用ガイドに既にあった |
| 7 | O-2 | `stop_grace_period: 20s` |
| 8a〜8g | 本PoC | P-1（`SYS_LISTEN_ERR` で終了コード 1）、P-2（`SYS_PANIC`）、P-3（HTTP の時間の上限）、P-4（`VALKEY_PASSWORD` の必須化、Valkey の healthcheck は `VALKEYCLI_AUTH` と PONG の確認）、P-5（起動ログの `build`、compose の `POC_VERSION`。provisioning-api の `version` は API の版のまま）、P-7（設定の検証、`VectorConnectTimeout` の削除。D-06・D-09 の「接続タイムアウト 2 秒」は実装されていなかったので文書を実装に合わせた）、P-11（`stop_grace_period: 20s`） |
| 8h | P-8 nonroot | 見送り（§4.2） |
| 8i | 本PoC の文書 | B-02(r24)、D-01(r24)、D-04(r38)、D-06(r19)、D-08(r28)、D-09(r23)、D-10(r16)、D-11(r14)、D-12(r11)、D-13(r8)、E-01(r10)、O-03(r14)、O-05(r25)、T-02(r25。134 ファイル、864 関数、1,531 ケース)、ドキュメント一覧(r66)、README |
| 9 | 確かめ方 | 単体テスト（保護を外すと失敗することも確かめた）、各リポジトリの CI、simwifi |
| 10 | healthcheck のログ | healthcheck の TCP 接続のたびに、サーバーが WARN（`http: TLS handshake error from 127.0.0.1:…: EOF`）を出し、aka-only-server ではメモリのログのバッファ（1,000 件）が約 80 分で埋まる。ループバックからのハンドシェイクの前の切断だけを DEBUG にする（外からの接続は WARN のまま） |

| リポジトリ | コミット | 内容 | CI |
|---|---|---|---|
| aka | `f0756ab`、`157ff8a` | A-1〜A-4、確認事項 10 | CI 3 ジョブ（compose で healthy を待つ通しを含む）と govulncheck が成功 |
| provisioner | `9a3a613`、`7ddd4c8`、`1c52058` | V-1〜V-4、確認事項 10、`POC_REF` を `0d5f53e`・`AKA_REF` を `157ff8a` に | CI 3 ジョブ（契約テストを含む）と govulncheck が成功 |
| OSS/BSS | `05293f1`、`ba2aa3f` | O-2、固定のコミットの更新（provisioner `1c52058`、本PoC `0d5f53e`、aka `157ff8a`） | CI 3 ジョブ（契約テストを含む）と govulncheck が成功 |
| 本PoC | develop `6666216`（#57）、main `0d5f53e`（#58） | P-1〜P-5・P-7・P-11、文書 | PR・main とも成功 |

simwifi での確認（2026-10-12。本PoC `8bc46ae`、aka `f0756ab`、provisioner `9a3a613`。片付け済み）:

- healthcheck のあるコンテナはすべて healthy。停止の猶予（StopTimeout）は aka-only-server 20、provisioner 30、vector-gateway・vector-api・provisioning-api 20。
- 5 つのアプリの起動ログに `"build":"8bc46ae"`（provisioning-api は `"version":"0.4.0"` と別）。
- 鍵の置き場所の違う加入者 2 人が EAP-AKA / EAP-AKA' で Accept。1 回の認証の `trace_id` が auth-server・vector-gateway・aka-only-server の 3 か所で一致した。
- auth-server の `LISTEN_ADDR` を bind できないアドレスにすると `SYS_LISTEN_ERR` を出して終了コード 1 で終わり、再起動を繰り返した（RestartCount が増える）。戻すと healthy。
- `VALKEY_PASSWORD` が空（または行がない）と `docker compose config` が断る。
- `docker compose stop` は 3 つとも 1〜2 秒で、強制終了（137）にならない。provisioner のログに `worker stopped`。
- `PROVISIONER_DOWNSTREAM_TIMEOUT=11s` では起動せず、10s では起動した。
- 停止・再開で Reject / Accept が変わった。
- 副作用（確認事項 10）を見つけた。直した後は、実際の TLS サーバーに healthcheck と同じ接続をしても INFO 以上のログが出ないことを単体テストで確かめた（直す前の作りでは WARN が出てテストが失敗する）。
