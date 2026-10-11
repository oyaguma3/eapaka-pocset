#!/usr/bin/env bash
# PoC セットの 4 つ（本PoC、aka-only-server、provisioner、OSS/BSS のサンプル）を、versions.env のコミットで
# 1 台のホストに導入し、eapaka_test で認証の流れを確かめる（計画書 §5 のステップ 5）。
#
# 使い方: scripts/e2e.sh [作業ディレクトリ]（既定 ./e2e-work）
#   KEEP=1 を付けると、終わった後もコンテナと作業ディレクトリを残す（調べるとき用）。
# 必要なもの: Docker（compose プラグイン）、git、curl、openssl、python3、sudo（provisioner の証明書の所有者を変える）。
# GitHub Actions（.github/workflows/e2e.yml）と、検証機（simwifi）の両方で動かす。待ち受けはすべてループバック。
#
# 導入の手順は各リポジトリの運用ガイドに従う（provisioner の運用ガイド 2 章、本PoC の B-02 §14・§15、
# aka-only-server の運用ガイド 3 章）。OSS/BSS のサンプルは、Cloudflare Access を使えないので、開発用の設定の
# バイナリで動かす（Access の検証は単体テストと検証機で確かめる）。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mkdir -p "${1:-$ROOT/e2e-work}" && cd "${1:-$ROOT/e2e-work}" && pwd)
SRC=$WORK/src
BIN=$WORK/bin
LOGS=$WORK/logs
CASES=$WORK/cases
mkdir -p "$SRC" "$BIN" "$LOGS" "$CASES"

# shellcheck source=../versions.env
source "$ROOT/versions.env"

POC=$SRC/eapaka-radius-server-poc
AKA=$SRC/aka-only-server
PROV=$SRC/eapaka-node-provisioner
OSSBSS=$SRC/eapaka-ossbss-sample
EAPAKA_TEST=$SRC/eapaka_test

# 試験の値。
PLMN_MAP=44010:01                   # 44010 で始まる IMSI の鍵は aka-only-server に置く
IMSI_POC=440200000000001            # 鍵を本PoC に置く加入者（provisioner の API で登録）
IMSI_AKA=440100000000001            # 鍵を aka-only-server に置く加入者（provisioner の API で登録）
IMSI_OSSBSS=440200000000002         # OSS/BSS のサンプルの画面から登録する加入者
IMSI_UNKNOWN=440200000000099        # 登録しない IMSI
KI=465b5ce8b199b49faa5f0a2ee238a6bc # 3GPP TS 35.208 Test Set 1
OPC=cd63cb71954a9f4e48a5994e37a02baf
NAS_ID=eapaka_test
SSID=MySSID
RADIUS_SECRET=testing123
PROV_URL=https://127.0.0.1:9446/admin/v1
OSSBSS_ADDR=127.0.0.1:18446
OSSBSS_USER=e2e@example.com
PG_CONTAINER=pocset-e2e-postgres
PG_PORT=25433

step() { printf '\n== %s\n' "$*"; }
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
pass() { echo "ok: $*"; }
rand() { openssl rand -hex 16; }
short() { echo "${1:0:7}"; }

# fingerprint は PEM の証明書の SHA-256 フィンガープリント（16 進小文字、区切りなし）を出す。
fingerprint() { openssl x509 -in "$1" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f'; }

# setenv は .env の項目を置き換える（なければ末尾に加える）。
setenv() {
	local file=$1 key=$2 value=$3
	if grep -q "^$key=" "$file"; then
		python3 - "$file" "$key" "$value" <<'EOF'
import sys
path, key, value = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines()
lines = [f"{key}={value}" if l.startswith(key + "=") else l for l in lines]
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
EOF
	else
		echo "$key=$value" >>"$file"
	fi
}

# fetch はリポジトリの決まったコミットを取得する（公開リポジトリなので認証は要らない）。
fetch() {
	local repo=$1 ref=$2 dir=$3
	rm -rf "$dir"
	git init -q "$dir"
	git -C "$dir" fetch -q --depth 1 "https://github.com/oyaguma3/$repo.git" "$ref"
	git -C "$dir" checkout -q FETCH_HEAD
	echo "$repo: $(git -C "$dir" log -1 --format='%h %s')"
}

# api は provisioner の API を呼ぶ（試験用の管理クライアント e2e として）。
api() {
	local method=$1 path=$2 body=${3:-}
	curl -sS --fail-with-body --cacert "$WORK/provisioner-server.pem" \
		--cert "$WORK/e2e-client.pem" --key "$WORK/e2e-client.pem" \
		-H 'X-Operator-Id: e2e' -H 'Content-Type: application/json' \
		-X "$method" "$PROV_URL$path" ${body:+-d "$body"}
}

# auth は eapaka_test で 1 回認証し、期待した結果（accept / reject）かを確かめる。
#   auth <説明> <IMSI> <aka|aka-prime> <accept|reject> [NAS-Identifier]
auth() {
	local desc=$1 imsi=$2 method=$3 expect=$4 nas=${5:-$NAS_ID}
	local prefix=0 prime=""
	if [[ $method == aka-prime ]]; then
		prefix=6
		# 本PoC の auth-server の EAP_AKA_PRIME_NETWORK_NAME の既定値
		prime=$'eap:\n  aka_prime:\n    net_name: "WLAN"'
	fi
	local cfg=$CASES/config-$imsi.yaml case=$CASES/case-$imsi-$method-$expect.yaml
	cat >"$cfg" <<EOF
radius:
  server_addr: "127.0.0.1:1812"
  secret: "$RADIUS_SECRET"
  timeout_ms: 3000
  retries: 2
radius_attrs:
  nas_ip_address: "192.0.2.10"
  nas_identifier: "$nas"
  called_station_id: "aa-bb-cc-dd-ee-ff:$SSID"
  calling_station_id: "00-11-22-33-44-55"
eap:
  method_mismatch_policy: "strict"
  outer_identity_update_on_permanent_req: true
  permanent_id_policy: "always"
  aka_prime:
    net_name: "WLAN"
identity:
  realm: "wlan.mnc010.mcc440.3gppnetwork.org"
sim:
  imsi: "$imsi"
  ki: "$KI"
  opc: "$OPC"
  amf: "8000"
  sqn_initial_hex: "000000000000"
sqn_store:
  mode: "file"
  path: "$CASES/sqn-$imsi.json"
EOF
	{
		echo "version: 1"
		echo "name: $desc"
		echo "identity: \"$prefix$imsi@wlan.mnc010.mcc440.3gppnetwork.org\""
		[[ -n $prime ]] && echo "$prime"
		echo "expect:"
		echo "  result: $expect"
		if [[ $expect == accept ]]; then
			echo "  mppe:"
			echo "    require_present: true"
		fi
	} >"$case"
	if "$BIN/eapaka_test" -c "$cfg" run "$case" >"$LOGS/eapaka_test-$imsi-$method-$expect.log" 2>&1; then
		pass "$desc（$imsi、$method → $expect）"
	else
		cat "$LOGS/eapaka_test-$imsi-$method-$expect.log" >&2
		fail "$desc（$imsi、$method、期待 $expect）"
	fi
}

# poc_logs は本PoC のサービスのログを出す。アプリのログは fluent-bit がホストのファイルにも書くが、fluentd の
# ログドライバーと fluent-bit を通るので届くのが遅れる。Docker が手元に残す控え（dual logging）から読む。
poc_logs() { (cd "$POC/deployments" && docker compose logs --no-color --no-log-prefix "$1" 2>/dev/null); }

# wait_log は、サービスのログに文字列が出るのを最大 30 秒待つ。
#   wait_log <poc|aka> <サービス> <文字列>
wait_log() {
	local where=$1 svc=$2 text=$3
	for _ in $(seq 30); do
		if [[ $where == poc ]]; then
			poc_logs "$svc" | grep -qF -- "$text" && return 0
		else
			(cd "$AKA" && docker compose logs --no-color --no-log-prefix "$svc" 2>/dev/null) | grep -qF -- "$text" && return 0
		fi
		sleep 1
	done
	return 1
}

# collect_logs は、各コンテナと OSS/BSS のサンプルのログを $LOGS に集める（失敗したときに CI の成果物にする）。
collect_logs() {
	set +e
	(cd "$AKA" 2>/dev/null && docker compose logs --no-color >"$LOGS/aka-only-server.log" 2>&1)
	(cd "$PROV" 2>/dev/null && docker compose logs --no-color >"$LOGS/eapaka-provisioner.log" 2>&1)
	(cd "$POC/deployments" 2>/dev/null && docker compose ps -a >"$LOGS/poc-ps.txt" 2>&1)
	(cd "$POC/deployments" 2>/dev/null && docker compose logs --no-color >"$LOGS/eapaka-radius-server-poc.log" 2>&1)
	# 本PoC のアプリのログは fluent-bit がホストのファイルに書く
	if [[ -d $POC/deployments/logs_on_host ]]; then
		sudo cp -r "$POC/deployments/logs_on_host" "$LOGS/poc-logs" && sudo chown -R "$(id -u):$(id -g)" "$LOGS/poc-logs"
	fi
	set -e
}

cleanup() {
	local rc=$?
	collect_logs
	if [[ ${KEEP:-0} == 1 ]]; then
		echo "KEEP=1 のため片付けない（作業ディレクトリ $WORK）"
		return
	fi
	set +e
	[[ -f $WORK/ossbss.pid ]] && kill "$(cat "$WORK/ossbss.pid")" 2>/dev/null
	docker rm -f -v "$PG_CONTAINER" >/dev/null 2>&1
	(cd "$PROV" 2>/dev/null && docker compose down -v --remove-orphans >/dev/null 2>&1)
	(cd "$POC/deployments" 2>/dev/null && docker compose down -v --remove-orphans >/dev/null 2>&1)
	(cd "$AKA" 2>/dev/null && docker compose down -v --remove-orphans >/dev/null 2>&1)
	# ログ以外を消す（certs や logs_on_host にはコンテナ（root や UID 65532）が書いたファイルがある）
	find "$WORK" -mindepth 1 -maxdepth 1 ! -name logs -exec sudo rm -rf {} +
	echo "片付けた（ログは $LOGS に残した）"
	return $rc
}
trap cleanup EXIT

step "ソースの取得（versions.env）"
fetch eapaka-radius-server-poc "$POC_REF" "$POC"
fetch aka-only-server "$AKA_REF" "$AKA"
fetch eapaka-node-provisioner "$PROVISIONER_REF" "$PROV"
fetch eapaka-ossbss-sample "$OSSBSS_REF" "$OSSBSS"
fetch eapaka_test "$EAPAKA_TEST_REF" "$EAPAKA_TEST"

step "試験の道具のビルド（eapaka_test、OSS/BSS のサンプル）"
# ホストに Go がなくても動くよう、コンテナでビルドする。
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e CGO_ENABLED=0 -e GOFLAGS=-buildvcs=false \
	-v "$EAPAKA_TEST:/src" -w /src golang:1.27.2 go build -o /src/eapaka_test.bin ./cmd/eapaka_test
mv "$EAPAKA_TEST/eapaka_test.bin" "$BIN/eapaka_test"
docker build -q -t pocset-e2e-ossbss --build-arg VERSION="$(short "$OSSBSS_REF")" "$OSSBSS" >/dev/null
cid=$(docker create pocset-e2e-ossbss)
docker cp -q "$cid:/eapaka-ossbss" "$BIN/eapaka-ossbss"
docker rm "$cid" >/dev/null
"$BIN/eapaka-ossbss" gen-client-cert -name ossbss-e2e >"$WORK/ossbss-client.pem" 2>/dev/null
pass "eapaka_test と eapaka-ossbss"

step "provisioner: ビルドとクライアント証明書（運用ガイド 2.1・2.2）"
cd "$PROV"
cp .env.example .env
setenv .env PROVISIONER_VALKEY_PASSWORD "$(rand)"
export PROVISIONER_VERSION AKA_VERSION POC_VERSION
PROVISIONER_VERSION=$(short "$PROVISIONER_REF")
docker compose -f compose.yaml build -q
mkdir -p certs
docker compose -f compose.yaml run --rm --no-deps -T eapaka-provisioner gen-client-cert -name provisioner >certs/client.pem 2>/dev/null </dev/null
docker compose -f compose.yaml run --rm --no-deps -T eapaka-provisioner gen-client-cert -name e2e >"$WORK/e2e-client.pem" 2>/dev/null </dev/null
FP_PROVISIONER=$(fingerprint certs/client.pem)
pass "provisioner のクライアント証明書 $FP_PROVISIONER"

step "aka-only-server: 起動と AVクライアントの登録（運用ガイド 2.3）"
cd "$AKA"
cp .env.example .env
setenv .env VALKEY_PASSWORD "$(rand)"
setenv .env AKA_AV_TLS_PUBLISH 127.0.0.1:8443
setenv .env AKA_ADMIN_CLIENTS "provisioner=$FP_PROVISIONER"
AKA_VERSION=$(short "$AKA_REF")
docker compose up -d --build --quiet-pull --wait --wait-timeout 300
mkdir -p "$POC/deployments/certs"
docker compose exec -T aka-only-server /aka-only-server client gen-cert -name radius-gw >"$POC/deployments/certs/av-client.pem" </dev/null
docker compose exec -T aka-only-server /aka-only-server client add -name radius-gw -cert - <"$POC/deployments/certs/av-client.pem" >/dev/null
docker compose exec -T aka-only-server /aka-only-server av-cert >"$POC/deployments/certs/av-server.pem" </dev/null
docker compose exec -T aka-only-server /aka-only-server admin-cert >"$PROV/certs/aka-server.pem" </dev/null
AV_CLIENT_ID=$(docker compose exec -T aka-only-server /aka-only-server client list </dev/null | awk '/name=radius-gw/ {print $1; exit}')
[[ -n $AV_CLIENT_ID ]] || fail "AVクライアント radius-gw の ID が分からない"
pass "aka-only-server が healthy、AVクライアント radius-gw の ID $AV_CLIENT_ID"

step "本PoC: 起動（B-02 §14・§15）"
cd "$POC/deployments"
cp .env.example .env
setenv .env VALKEY_PASSWORD "$(rand)"
setenv .env VECTOR_GATEWAY_PLMN_MAP "$PLMN_MAP"
setenv .env VECTOR_GATEWAY_AKAONLY_URL https://aka-only-server:8443
setenv .env VECTOR_GATEWAY_AKAONLY_CLIENT_CERT /certs/av-client.pem
setenv .env VECTOR_GATEWAY_AKAONLY_SERVER_CERT /certs/av-server.pem
setenv .env PROVISIONING_API_ADMIN_CLIENTS "provisioner=$FP_PROVISIONER"
setenv .env PROVISIONING_API_NODE_NAME e2e
setenv .env COMPOSE_PROFILES provisioning
setenv .env COMPOSE_FILE docker-compose.yml:docker-compose.aka-av.yml:docker-compose.override.yml
# RADIUS のポートもループバックに限る（検証機で外から届かないようにする）
cat >docker-compose.override.yml <<'EOF'
services:
  auth-server:
    ports: !override
      - "127.0.0.1:1812:1812/udp"
  acct-server:
    ports: !override
      - "127.0.0.1:1813:1813/udp"
EOF
mkdir -p certs/provisioning
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
	-keyout certs/provisioning/server.key -out certs/provisioning/server.pem \
	-days 30 -subj "/CN=provisioning-api" \
	-addext "subjectAltName=DNS:provisioning-api,DNS:localhost,IP:127.0.0.1" 2>/dev/null
chmod 600 certs/provisioning/server.key
POC_VERSION=$(short "$POC_REF")
docker compose up -d --build --quiet-pull --wait --wait-timeout 600
pass "本PoC が起動（healthcheck のあるものは healthy）"

step "provisioner: 起動（運用ガイド 2.4〜2.7）"
cd "$PROV"
cp "$POC/deployments/certs/provisioning/server.pem" certs/prov-server.pem
sudo chown 65532:65532 certs/*.pem
sudo chmod 600 certs/*.pem
setenv .env PROVISIONER_ADMIN_CLIENTS "e2e=$(fingerprint "$WORK/e2e-client.pem"),ossbss=$(fingerprint "$WORK/ossbss-client.pem")"
setenv .env PROVISIONER_AKA_URL https://aka-only-server:9443/admin/v1
setenv .env PROVISIONER_AKA_AV_CLIENT_ID "$AV_CLIENT_ID"
setenv .env PROVISIONER_PLMN_MAP "$PLMN_MAP"
docker compose up -d --quiet-pull --wait --wait-timeout 180
docker compose exec -T eapaka-provisioner /eapaka-provisioner check-downstream </dev/null >"$LOGS/check-downstream.txt" 2>&1 ||
	{
		cat "$LOGS/check-downstream.txt" >&2
		fail "check-downstream"
	}
docker compose exec -T eapaka-provisioner /eapaka-provisioner server-cert >"$WORK/provisioner-server.pem" 2>/dev/null </dev/null
pass "provisioner が healthy、check-downstream で下流 2 つと AVクライアントに接続できた"

step "起動ログのビルドの版"
for app in auth-server acct-server vector-gateway vector-api provisioning-api; do
	wait_log poc "$app" "\"build\":\"$POC_VERSION\"" || fail "$app の起動ログに build $POC_VERSION がない"
done
pass "本PoC の 5 つのアプリの起動ログに build $POC_VERSION"

step "provisioner の API で RADIUSクライアントと加入者を登録"
GATEWAY=$(docker network inspect deployments_default -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
api POST /clients "{\"ip\":\"$GATEWAY\",\"secret\":\"$RADIUS_SECRET\",\"name\":\"e2e\"}" >/dev/null
POLICY="{\"default\":\"deny\",\"rules\":[{\"nasId\":\"$NAS_ID\",\"allowedSsids\":[\"$SSID\"]}]}"
for imsi in "$IMSI_POC" "$IMSI_AKA"; do
	api POST /subscribers "{\"imsi\":\"$imsi\",\"ki\":\"$KI\",\"opc\":\"$OPC\",\"policy\":$POLICY}" >"$WORK/sub-$imsi.json"
done
python3 - "$WORK/sub-$IMSI_POC.json" "$WORK/sub-$IMSI_AKA.json" <<'EOF' || fail "鍵の置き場所が期待と違う"
import json, sys
got = [json.load(open(p))["keyStore"] for p in sys.argv[1:]]
assert got == ["poc", "aka"], got
EOF
pass "RADIUSクライアント（$GATEWAY）、加入者 $IMSI_POC（本PoC）・$IMSI_AKA（aka-only-server）"

step "認証（EAP-AKA / EAP-AKA'）"
auth "本PoC に鍵がある加入者" "$IMSI_POC" aka accept
auth "本PoC に鍵がある加入者" "$IMSI_POC" aka-prime accept
auth "aka-only-server に鍵がある加入者" "$IMSI_AKA" aka accept
auth "aka-only-server に鍵がある加入者" "$IMSI_AKA" aka-prime accept

step "拒否されること"
auth "登録していない IMSI" "$IMSI_UNKNOWN" aka reject
auth "認可ポリシーにない NAS" "$IMSI_POC" aka reject other-nas

step "停止と再開（provisioner の API）"
api PUT "/policies/$IMSI_AKA/status" '{"status":"suspended"}' >/dev/null
auth "停止中の加入者" "$IMSI_AKA" aka reject
auth "停止していない加入者" "$IMSI_POC" aka accept
api PUT "/policies/$IMSI_AKA/status" '{"status":"active"}' >/dev/null
auth "再開した加入者" "$IMSI_AKA" aka accept
wait_log poc auth-server '"event_id":"AUTH_SUBSCRIBER_SUSPENDED"' || fail "auth-server に AUTH_SUBSCRIBER_SUSPENDED がない"
pass "停止で Reject（AUTH_SUBSCRIBER_SUSPENDED）、再開で Accept"

step "トレースID（auth-server と aka-only-server）"
cd "$AKA"
TRACE=$(docker compose logs --no-color --no-log-prefix aka-only-server 2>/dev/null |
	python3 -c 'import json,sys
ids=[]
for l in sys.stdin:
    try: e=json.loads(l)
    except ValueError: continue
    if e.get("msg")=="av generated" and e.get("trace_id"): ids.append(e["trace_id"])
print(ids[-1] if ids else "")')
[[ -n $TRACE ]] || fail "aka-only-server の払い出しのログに trace_id がない"
wait_log poc auth-server "\"trace_id\":\"$TRACE\"" || fail "aka-only-server の trace_id $TRACE が auth-server のログにない"
pass "aka-only-server の払い出しの trace_id $TRACE が auth-server のログにもある"

step "OSS/BSS のサンプル（開発用の設定）"
PG_PASSWORD=$(rand)
docker run -d --name "$PG_CONTAINER" -p "127.0.0.1:$PG_PORT:5432" -e POSTGRES_USER=ossbss \
	-e POSTGRES_PASSWORD="$PG_PASSWORD" -e POSTGRES_DB=ossbss postgres:18.6 >/dev/null
for _ in $(seq 60); do
	docker exec "$PG_CONTAINER" pg_isready -U ossbss -d ossbss >/dev/null 2>&1 && break
	sleep 1
done
OSSBSS_ADDR=$OSSBSS_ADDR OSSBSS_DEV_USER_EMAIL=$OSSBSS_USER OSSBSS_INITIAL_ADMIN_EMAIL=$OSSBSS_USER \
	OSSBSS_DB_ADDR=127.0.0.1:$PG_PORT OSSBSS_DB_PASSWORD=$PG_PASSWORD \
	OSSBSS_PROVISIONER_URL=$PROV_URL OSSBSS_PROVISIONER_CLIENT_CERT=$WORK/ossbss-client.pem \
	OSSBSS_PROVISIONER_SERVER_CERT=$WORK/provisioner-server.pem \
	nohup "$BIN/eapaka-ossbss" serve >"$LOGS/eapaka-ossbss.log" 2>&1 &
echo $! >"$WORK/ossbss.pid"
for _ in $(seq 60); do
	curl -sf "http://$OSSBSS_ADDR/healthz" >/dev/null && break
	sleep 1
done
curl -sf "http://$OSSBSS_ADDR/healthz" >/dev/null || fail "OSS/BSS のサンプルが起動しない"
# 加入者の登録（運用担当・システム管理者の画面。所属はテナントなし、認可ポリシーは既定 allow）
code=$(curl -s -o "$LOGS/ossbss-create.html" -w '%{http_code}' -X POST "http://$OSSBSS_ADDR/subscribers" \
	--data-urlencode tenant=none --data-urlencode "imsi=$IMSI_OSSBSS" --data-urlencode "ki=$KI" \
	--data-urlencode "opc=$OPC" --data-urlencode amf=8000 --data-urlencode sqn=000000000000 \
	--data-urlencode default=allow --data-urlencode idem="e2e-create-$(rand)")
[[ $code == 303 ]] || fail "OSS/BSS のサンプルからの加入者の登録（HTTP $code）"
auth "OSS/BSS のサンプルから登録した加入者" "$IMSI_OSSBSS" aka accept
ossbss_status() {
	local status=$1 code
	code=$(curl -s -o "$LOGS/ossbss-status-$status.html" -w '%{http_code}' -X POST \
		"http://$OSSBSS_ADDR/subscribers/$IMSI_OSSBSS/status" \
		--data-urlencode "status=$status" --data-urlencode status_idem="e2e-$status-$(rand)")
	[[ $code == 200 || $code == 303 ]] || fail "OSS/BSS のサンプルからの $status（HTTP $code）"
}
ossbss_status suspended
auth "OSS/BSS のサンプルから停止した加入者" "$IMSI_OSSBSS" aka reject
ossbss_status active
auth "OSS/BSS のサンプルから再開した加入者" "$IMSI_OSSBSS" aka accept
actions=$(docker exec "$PG_CONTAINER" psql -U ossbss -d ossbss -tAc \
	"select string_agg(action, ',' order by id) from audit_log where target = '$IMSI_OSSBSS'")
[[ $actions == "subscriber.create,policy.suspend,policy.resume" ]] ||
	fail "OSS/BSS のサンプルの監査ログ（$actions）"
pass "OSS/BSS のサンプルの監査ログ: $actions"

step "本PoC の Valkey の再起動の後も認証できる"
cd "$POC/deployments"
docker compose restart valkey >/dev/null
docker compose up -d --wait --wait-timeout 120 valkey >/dev/null
auth "Valkey の再起動の後" "$IMSI_POC" aka accept

step "すべて成功"
