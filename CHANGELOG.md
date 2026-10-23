# CHANGELOG

PoC セットのタグごとに、各リポジトリで変わったことを書く。組み合わせ（各リポジトリのコミット）は、そのタグの `versions.env` にある。計画と経緯は `docs/plan.md`。

## pocset-v1.0.1（2026-10-24）

Go の `crypto/x509` のセキュリティ修正を取り込むための版。4 つのソフトウェアの API と機能は変えていない。

### 4 つに共通

- Go を 1.27.3 に上げた（go.mod、Dockerfile、CI）。Go 1.27.3 は `crypto/x509` の CVE-2026-111943（[GO-2026-6809](https://pkg.go.dev/vuln/GO-2026-6809)）を直す。認証局 eMudhra の中間 CA 8 件の秘密鍵が推測できる弱い鍵だったため、これらを含む証明書チェーンを `Certificate.Verify` で拒む。Go 1.27.2 のままだと govulncheck が指摘する。
- PoC セットの mTLS は、すべて自前の証明書と自前のルートで行うので、この件による実害はない。OS のルートを使うのは OSS/BSS のサンプルが Cloudflare Access の公開鍵を取りに行く通信だけで、Cloudflare は eMudhra の証明書を使っていない。

### PoC セット（eapaka-pocset）

- `versions.env` を 4 つの新しいコミットに更新した。`scripts/e2e.sh` が eapaka_test をビルドするイメージを `golang:1.27.3` にした。
- README の「状態」の行を直した（最初のタグの前のままだった）。

### 本PoC（eapaka-radius-server-poc）

- 文書: Go の版を書いた文書を改版した（ドキュメント一覧 r69）。

### eapaka-ossbss-sample

- cloudflared を 2026.9.3 から 2026.10.3 にした（2026.9.3 は Go 1.26.8 でビルドされていて GO-2026-6809 の対象。2026.10.3 は Go 1.27.3）。

### 導入済みの環境の更新

- 4 つとも、新しいタグを取得してイメージをビルドし直す。ベースイメージとビルドのキャッシュの古い層が残らないように、`docker compose build --pull --no-cache` を使う。今のベースイメージ（本PoC の `debian:12.15-slim` に入れる ca-certificates 20250419~deb12u2、`distroless/static-debian13`）は、信頼を取り消された emSign ECC Root CA - G3 を含まない。

## pocset-v1.0.0（2026-10-19）

PoC セットとしての最初の版。4 つのソフトウェアの機能はそのままに、品質と安定性を上げ、組み合わせを確かめた（`docs/plan.md` のステップ 1〜7）。

### PoC セット（eapaka-pocset）

- 組み合わせの表 `versions.env` と、4 つを 1 台に compose で導入して認証の流れを確かめる試験 `scripts/e2e.sh`（GitHub Actions の E2E。push、PR、毎週月曜）。
- provisioner と OSS/BSS のサンプルの CI が固定しているコミットが `versions.env` と一致するかの確認 `scripts/check-pins.sh`。
- README に 1 台への導入の案内。

### 4 つに共通

- Go を 1.27.2 にそろえた（本PoC は 1.25.5 から。1.25 系はサポートが終わっている）。
- イメージの版をパッチ版まで固定した（例 `valkey/valkey:9.1.2`、`postgres:18.6`、`golang:1.27.2`。distroless は版のタグがないので例外）。第三者の GitHub Action はコミットの SHA で固定した。
- govulncheck を CI に加えた（push・PR と毎週月曜）。指摘のあった依存を上げた（本PoC の `golang.org/x/net`・`quic-go`、OSS/BSS のサンプルの `golang.org/x/text`）。
- README に PoC セットへの案内を加えた。

### 本PoC（eapaka-radius-server-poc）

- auth-server・acct-server: 待ち受けを開始できない（ポートが使用中など）ときは、ERROR（`SYS_LISTEN_ERR`）を出して終了コード 1 で終わる（以前はログだけで終了せず、healthcheck が healthy のままだった）。パケットの処理中のパニックを回復する（`SYS_PANIC`）。
- vector-api・vector-gateway: HTTP サーバーに時間の上限を設けた。設定の検証を足した（`VECTOR_GATEWAY_INTERNAL_TIMEOUT` が 0 以下、テストベクターモードの IMSI の前方一致が数字以外なら起動しない）。
- compose: `VALKEY_PASSWORD` が空なら起動を断る。Valkey の healthcheck はパスワードを環境変数で渡し、PONG を確かめる。停止の猶予（`stop_grace_period`）を設けた。5 つのアプリにビルドの版を埋め込み、起動ログに `build` として出す（`POC_VERSION`）。
- Valkey を 9.0 から 9.1.2 に、ランタイムのベースイメージを `debian:12.15-slim` に、Fluent Bit を 4.2.8 にした。
- CI: gofmt、golangci-lint v2.14.0、イメージ 5 つのビルドと compose の設定、govulncheck を加えた。
- 文書: 実装に合わせて改版した（ドキュメント一覧 r65〜r68）。他の文書を参照するときに版数を書かない方針にし、git の管理外の作業資料へのリンクを外した。テストの文書（T-01 テスト戦略書、T-02 単体テスト仕様書の環境とモックの決まり）を実装と照合して直した。

### aka-only-server

- 認証ベクターAPI で `X-Trace-ID` を受け取り、払い出しのログに `trace_id` を残す（認証ベクターAPI 0.2.0-draft）。本PoC の vector-gateway が付けるトレースID で、1 回の認証を 4 つのログでたどれる。
- `healthcheck` サブコマンドと compose の healthcheck、停止の猶予 20 秒。healthcheck の接続によるログ（ハンドシェイクの切断）は DEBUG にした。
- `AKA_VERSION` を `.env.example` と文書に書いた。

### eapaka-node-provisioner

- やり直しのワーカーが、パニックを回復して次の操作へ進み、停止のときは処理中の操作を終えてから終わる。
- `PROVISIONER_DOWNSTREAM_TIMEOUT` が 10 秒を超えたら起動しない（1 つの操作は下流を順に最大 5 回呼ぶので、IMSI のロックの 60 秒に収める）。
- `healthcheck` サブコマンドと compose の healthcheck、停止の猶予 30 秒。healthcheck の接続によるログは DEBUG にした。

### eapaka-ossbss-sample

- 停止の猶予を 20 秒にした。

### 既知の制約

- 本PoC のコンテナは root で動く（nonroot にすると、導入済みの環境で証明書の鍵の所有者を変える手順が要るため見送った。待ち受けは特権のいらないポートだけ）。
- aka-only-server と provisioner の healthcheck は、mTLS のため TCP で接続できるかだけを見る。
- OSS/BSS のサンプルの Cloudflare Access での認証は、4 つを通した試験では確かめない（開発用の設定で動かす）。単体テストと検証機で確かめる。
- 本PoC の結合試験（T-03）と E2E（T-04）は、手順書で行う。主な流れは `scripts/e2e.sh` で自動で確かめる。
