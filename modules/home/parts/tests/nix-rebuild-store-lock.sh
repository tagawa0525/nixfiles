#!/usr/bin/env bash
# =============================================================================
# nix-rebuild の switch が、ストアの DB の排他ロック（big-lock）の待ちで黙って止まらないことを検証する
# =============================================================================
# 実際に起きたこと（#694）: nix の版が上がって DB の migration が入ると、root の nix が big-lock の排他ロックを求める。
# nix-daemon のワーカーは、クライアントがつながっている間ずっと big-lock を共有で持つ。nixd の評価プロセス
# （nixd-attrset-eval）が何日もつないだままだったので、switch が何も出さずに待ち続けた。
#
# 使い方（リポジトリルートで実行）:
#   ./modules/home/parts/tests/nix-rebuild-store-lock.sh
#
# sudo はスタブに差し替え、/proc/locks と big-lock は一時のファイルに向ける。実システムには触れない。
# nix-daemon のワーカーとクライアントは、同じ引数の並びを持つ本物のプロセス（中身は sleep）で作る。

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$ROOT/modules/home/scripts/nix-rebuild.sh"

WORK=$(mktemp -d)
PIDS=()
cleanup() {
  local p
  for p in "${PIDS[@]}"; do kill -KILL "$p" 2> /dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

export HOME="$WORK/home"
mkdir -p "$HOME/nix" "$WORK/bin"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

# main 以外のブランチの rebuild は、何も取り込まずに switch まで進む
REPO="$HOME/nix/nixfiles"
git init -q "$REPO"
echo x > "$REPO/x"
git -C "$REPO" add x
git -C "$REPO" commit -qm "chore: init"
git -C "$REPO" switch -qc feat/x

export PATH="$WORK/bin:$PATH"
export NIX_REBUILD_STORE_LOCK="$WORK/big-lock"
export NIX_REBUILD_PROC_LOCKS="$WORK/locks"
export NIX_REBUILD_LOCK_POLL=0.2
touch "$NIX_REBUILD_STORE_LOCK"
INODE=$(stat -c %i "$NIX_REBUILD_STORE_LOCK")

PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  echo "✓ $1"
}
ng() {
  FAIL=$((FAIL + 1))
  echo "✗ $1" >&2
  sed 's/^/    /' "$WORK/out" >&2
}
check() {
  local name=$1
  shift
  if "$@"; then ok "$name"; else ng "$name"; fi
}

# 引数の並びが「$1 $2」のプロセスを起動し、pid を SPAWNED に入れる。中身は、書き手のいない fifo を読んで待ち続ける
# bash（coreutils の sleep は、引数の先頭でプログラムを選ぶので名前を変えられない）
mkdir -p "$WORK/scripts"
mkfifo "$WORK/hold"
spawn() {
  local name=$1 arg=${2:-run}
  echo "read -r _ < '$WORK/hold'" > "$WORK/scripts/$arg"
  (cd "$WORK/scripts" && exec -a "$name" bash "$arg") &
  SPAWNED=$!
  PIDS+=("$SPAWNED")
}

# nix-daemon のワーカー（プロセスの題名は「nix-daemon <クライアントの pid>」）
spawn_worker() {
  spawn nix-daemon "$1"
}

alive() { kill -0 "$1" 2> /dev/null; }
gone() { ! alive "$1"; }
said() { grep -q -- "$1" "$WORK/out"; }
not_said() { ! said "$1"; }

# /proc/locks の形。待ちの行は「->」が付く
holder_line() { echo "1: FLOCK  ADVISORY  READ $1 00:24:$INODE 0 EOF"; }
waiter_line() { echo "1: -> FLOCK  ADVISORY  WRITE $1 00:24:$INODE 0 EOF"; }

# sudo のスタブ: $1 の pid が消えるまで待つ（switch が排他ロックを待つ様子）。4 秒で諦めて失敗する
sudo_waits_for() {
  cat > "$WORK/bin/sudo" << EOF
#!/bin/sh
i=0
while kill -0 $1 2>/dev/null; do
  i=\$((i + 1))
  [ \$i -gt 40 ] && exit 1
  sleep 0.1
done
exit 0
EOF
  chmod +x "$WORK/bin/sudo"
}

# sudo のスタブ: $1 秒かけて、終了コード $2 で終わる
sudo_takes() {
  printf '#!/bin/sh\nsleep %s\nexit %s\n' "$1" "$2" > "$WORK/bin/sudo"
  chmod +x "$WORK/bin/sudo"
}

run_rebuild() { bash "$SCRIPT" rebuild > "$WORK/out" 2>&1; }

echo "==> nixd の評価プロセスが big-lock を持たせていて、排他ロックが待っている"
spawn nixd-attrset-eval
nixd=$SPAWNED
spawn_worker "$nixd"
worker=$SPAWNED
{
  holder_line "$worker"
  waiter_line 999999
} > "$NIX_REBUILD_PROC_LOCKS"
sudo_waits_for "$nixd"
check "switch が先へ進んで成功する" run_rebuild
check "nixd の評価プロセスを止める" gone "$nixd"
check "止めたプロセスを知らせる" said "nixd-attrset-eval.*$nixd"

echo "==> nixd 以外のクライアントが big-lock を持たせていて、排他ロックが待っている"
spawn some-nix-client
client=$SPAWNED
spawn_worker "$client"
worker=$SPAWNED
{
  holder_line "$worker"
  waiter_line 999999
} > "$NIX_REBUILD_PROC_LOCKS"
sudo_takes 1.5 0
check "switch の終了コードをそのまま返す" run_rebuild
check "クライアントは止めない" alive "$client"
check "つないだままのプロセスを知らせる" said "$client.*some-nix-client"
check "同じプロセスは 1 回だけ知らせる" test "$(grep -c -- "some-nix-client" "$WORK/out")" = 1

echo "==> big-lock を持つプロセスはあるが、排他ロックを待つものがない（普段の rebuild）"
spawn nixd-attrset-eval
nixd=$SPAWNED
spawn_worker "$nixd"
worker=$SPAWNED
holder_line "$worker" > "$NIX_REBUILD_PROC_LOCKS"
sudo_takes 1.5 0
check "成功する" run_rebuild
check "nixd の評価プロセスを止めない" alive "$nixd"
check "何も知らせない" not_said "nixd-attrset-eval"

echo "==> 別のファイルの排他ロックが待っている"
{
  echo "1: FLOCK  ADVISORY  READ $worker 00:24:${INODE}0 0 EOF"
  echo "1: -> FLOCK  ADVISORY  WRITE 999999 00:24:${INODE}0 0 EOF"
} > "$NIX_REBUILD_PROC_LOCKS"
sudo_takes 1.5 0
check "成功する" run_rebuild
check "nixd の評価プロセスを止めない" alive "$nixd"

echo "==> switch が失敗する"
: > "$NIX_REBUILD_PROC_LOCKS"
sudo_takes 0 1
if run_rebuild; then ng "失敗終了する"; else ok "失敗終了する"; fi
sleep 0.5
check "監視のプロセスを残さない" test -z "$(pgrep -f "$SCRIPT" || true)"

echo
echo "passed: $PASS, failed: $FAIL"
((FAIL == 0))
