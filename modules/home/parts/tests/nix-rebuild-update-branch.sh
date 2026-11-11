#!/usr/bin/env bash
# =============================================================================
# nix-rebuild update が main 以外のブランチでは何もせずに止まることと、進める input の選び方を検証する
# =============================================================================
# update は「origin/main を取り込み、lock を更新・検証して main に push する」処理。
# 実際に起きた事故: PR ブランチをチェックアウトしたまま update を実行し、
# PR ブランチが main 上へリベースされ、flake.lock のコミットが PR ブランチに
# 積まれて push された（PR #239）。
#
# 使い方（リポジトリルートで実行）:
#   ./modules/home/parts/tests/nix-rebuild-update-branch.sh
#
# nix / sudo はスタブに差し替え、ネットワークにも実システムにも触れない。

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
# リポジトリ内のファイルには実行ビットがない（home.file 側で付く）ため bash で呼ぶ
SCRIPT="$ROOT/modules/home/scripts/nix-rebuild.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# スクリプトは NIXDIR=~/nix/nixfiles 固定なので HOME ごと差し替える
export HOME="$WORK/home"
mkdir -p "$HOME/nix"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

# 実システムに触れないよう nix / sudo は失敗するスタブにする。
# ガードを通過した場合は nix flake update の呼び出しで止まる
mkdir -p "$WORK/bin"
for cmd in nix sudo; do
  printf '#!/bin/sh\necho "stub %s called" >&2\nexit 1\n' "$cmd" > "$WORK/bin/$cmd"
  chmod +x "$WORK/bin/$cmd"
done
# nix のスタブは、受けた引数も 1 回の呼び出しを 1 行にして残す
printf '#!/bin/sh\necho "$*" >> "%s/nix.args"\necho "stub nix called" >&2\nexit 1\n' "$WORK" > "$WORK/bin/nix"
export PATH="$WORK/bin:$PATH"

# origin（bare）と clone を用意し、origin/main を clone より 1 コミット進める
git init -q --bare "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$HOME/nix/nixfiles" 2>/dev/null
REPO="$HOME/nix/nixfiles"
echo '{}' > "$REPO/flake.lock"
git -C "$REPO" add flake.lock
git -C "$REPO" commit -qm "chore: init"
git -C "$REPO" push -q origin main
git -C "$REPO" switch -qc feat/x
echo x > "$REPO/x"
git -C "$REPO" add x
git -C "$REPO" commit -qm "feat: x"
git clone -q "$WORK/origin.git" "$WORK/other"
echo y > "$WORK/other/y"
git -C "$WORK/other" add y
git -C "$WORK/other" commit -qm "feat: y"
git -C "$WORK/other" push -q origin main

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "✓ $1"; }
ng() { FAIL=$((FAIL + 1)); echo "✗ $1" >&2; sed 's/^/    /' "$WORK/out" >&2; }

echo "==> feature branch 上の update"
before=$(git -C "$REPO" rev-parse HEAD)
# origin/main は clone 後に other から進めてあり、ローカルの追跡 ref は古いまま
tracking_before=$(git -C "$REPO" rev-parse origin/main)
if bash "$SCRIPT" update >"$WORK/out" 2>&1; then
  ng "失敗終了する"
else
  ok "失敗終了する"
fi
if [[ "$(git -C "$REPO" rev-parse HEAD)" == "$before" ]]; then
  ok "ブランチを動かさない（main 上へリベースしない）"
else
  ng "ブランチを動かさない（main 上へリベースしない）"
fi
if [[ "$(git -C "$REPO" rev-parse origin/main)" == "$tracking_before" ]]; then
  ok "fetch しない（origin/main の追跡 ref が古いまま）"
else
  ng "fetch しない（origin/main の追跡 ref が古いまま）"
fi
if grep -q "main ブランチで実行してください（現在: feat/x）" "$WORK/out"; then
  ok "現在のブランチと main で実行すべき旨を出力する"
else
  ng "現在のブランチと main で実行すべき旨を出力する"
fi
if grep -q "stub nix called" "$WORK/out"; then
  ng "nix を呼ばない"
else
  ok "nix を呼ばない"
fi

echo "==> detached HEAD 上の update"
git -C "$REPO" switch -q --detach main
if bash "$SCRIPT" update >"$WORK/out" 2>&1 || grep -q "stub nix called" "$WORK/out"; then
  ng "nix を呼ばずに失敗終了する"
else
  ok "nix を呼ばずに失敗終了する"
fi

echo "==> main 上の update はガードを通過する"
git -C "$REPO" switch -q main
bash "$SCRIPT" update >"$WORK/out" 2>&1 || true
if grep -q "stub nix called" "$WORK/out"; then
  ok "nix flake update まで進む"
else
  ng "nix flake update まで進む"
fi

echo "==> update は、引数が無ければすべての input を、あれば挙げた input だけを進める"
rm -f "$WORK/nix.args"
bash "$SCRIPT" update >"$WORK/out" 2>&1 || true
if [[ "$(cat "$WORK/nix.args" 2>/dev/null)" == "flake update" ]]; then
  ok "引数の無い update は nix flake update を呼ぶ"
else
  ng "引数の無い update は nix flake update を呼ぶ"
fi
# ハーネスの直しだけを反映する（その日の nixpkgs のビルドの失敗に巻き込まれない）
rm -f "$WORK/nix.args"
bash "$SCRIPT" update claude-harness >"$WORK/out" 2>&1 || true
if [[ "$(cat "$WORK/nix.args" 2>/dev/null)" == "flake update claude-harness" ]]; then
  ok "update claude-harness は nix flake update claude-harness を呼ぶ"
else
  ng "update claude-harness は nix flake update claude-harness を呼ぶ"
fi

echo
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
