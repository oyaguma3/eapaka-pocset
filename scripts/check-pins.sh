#!/usr/bin/env bash
# provisioner と OSS/BSS のサンプルの CI が契約テストの相手として固定しているコミットが、versions.env の
# 組み合わせと一致するかを確かめる（計画書 §6 のリリースの基準）。違えば終了コード 1。
# 使い方: scripts/check-pins.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../versions.env
source "$ROOT/versions.env"

status=0

# check は、リポジトリの ref の ci.yml に書かれた「名前: 値」が、期待するコミットかを確かめる。
check() {
	local repo=$1 ref=$2 name=$3 want=$4 got
	got=$(curl -sSf "https://raw.githubusercontent.com/oyaguma3/$repo/$ref/.github/workflows/ci.yml" |
		sed -n "s/^ *$name: *\([0-9a-f]*\).*/\1/p" | head -1)
	if [[ $got == "$want" ]]; then
		echo "ok: $repo（${ref:0:7}）の $name = ${want:0:7}"
	else
		echo "NG: $repo（${ref:0:7}）の $name = ${got:-（なし）}、versions.env では $want" >&2
		status=1
	fi
}

check eapaka-node-provisioner "$PROVISIONER_REF" POC_REF "$POC_REF"
check eapaka-node-provisioner "$PROVISIONER_REF" AKA_REF "$AKA_REF"
check eapaka-ossbss-sample "$OSSBSS_REF" PROVISIONER_REF "$PROVISIONER_REF"
check eapaka-ossbss-sample "$OSSBSS_REF" POC_REF "$POC_REF"
check eapaka-ossbss-sample "$OSSBSS_REF" AKA_REF "$AKA_REF"

exit $status
