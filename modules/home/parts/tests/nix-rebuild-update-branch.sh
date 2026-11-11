#!/usr/bin/env bash
# =============================================================================
# nix-rebuild の update と rebuild が、origin/main をどう取り込むか（ブランチの扱い、進める input の選び方）を検証する
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
# input の名前を確かめる先（flake.lock の root の inputs）
LOCK0='{"nodes":{"root":{"inputs":{"claude-harness":"claude-harness","nixpkgs":"nixpkgs"}}}}'
echo "$LOCK0" > "$REPO/flake.lock"
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
# 名前を確かめるのは input を挙げたときだけ。毎朝の自動更新（引数なし）を、jq と lock の形に頼らせない
printf '#!/bin/sh\necho "stub jq called" >&2\nexit 1\n' > "$WORK/bin/jq"
chmod +x "$WORK/bin/jq"
rm -f "$WORK/nix.args"
bash "$SCRIPT" update >"$WORK/out" 2>&1 || true
if [[ "$(cat "$WORK/nix.args" 2>/dev/null)" == "flake update" ]] && ! grep -q "stub jq called" "$WORK/out"; then
  ok "引数の無い update は、jq を呼ばずに nix flake update まで進む"
else
  ng "引数の無い update は、jq を呼ばずに nix flake update まで進む"
fi
rm -f "$WORK/bin/jq"
# nix flake update は、flake に無い input の名前を警告だけで通す（終了コード 0）。打ち間違いのまま検証と切り替えまで
# 進み、直しが入っていないのに成功に見える
for bad in claude-harnes --commit-lock-file; do
  rm -f "$WORK/nix.args"
  if bash "$SCRIPT" update "$bad" >"$WORK/out" 2>&1; then
    ng "flake に無い input の名前（$bad）では失敗終了する"
  elif [[ -e "$WORK/nix.args" ]]; then
    ng "flake に無い input の名前（$bad）では nix を呼ばない"
  elif ! grep -qF -- "$bad" "$WORK/out" || ! grep -q "claude-harness" "$WORK/out"; then
    ng "flake に無い input の名前（$bad）と、使える名前の一覧を出力する"
  else
    ok "flake に無い input の名前（$bad）では、nix を呼ばずに、使える名前を示して失敗終了する"
  fi
done

echo "==> update は、lock を進めた後、検証のビルドと切り替えの前に、ハーネスとの約束の照合を通す"
# nix は成功するスタブにする（flake update は lock を書き換え、eval はホストの名前を、build はパスを返す）
cat > "$WORK/bin/nix" <<STUB
#!/bin/sh
echo "\$1" >> "$WORK/nix.calls"
case "\$1 \$2" in
  "flake update") echo '{"updated":true}' > "$REPO/flake.lock" ;;
  "eval "*) printf 'testhost' ;;
  "build "*) echo /nix/store/fake-toplevel ;;
esac
STUB
printf '#!/bin/sh\necho "stub sudo called" >&2\nexit 1\n' > "$WORK/bin/sudo"
mkdir -p "$REPO/modules/home/parts/tests"
CONTRACT="$REPO/modules/home/parts/tests/harness-contract.sh"

printf '#!/usr/bin/env bash\necho "contract ng"\nexit 1\n' > "$CONTRACT"
rm -f "$WORK/nix.calls"
if bash "$SCRIPT" update >"$WORK/out" 2>&1; then
  ng "照合が落ちたら失敗終了する"
else
  ok "照合が落ちたら失敗終了する"
fi
if grep -q "stub sudo called" "$WORK/out"; then
  ng "照合が落ちたら切り替えない"
else
  ok "照合が落ちたら切り替えない"
fi
if [[ "$(cat "$REPO/flake.lock")" == "$LOCK0" ]]; then
  ok "照合が落ちたら flake.lock を戻す"
else
  ng "照合が落ちたら flake.lock を戻す"
fi
# 照合に要るのはハーネスのソースと hook だけ。全ホストのビルドを終えてから落とすと、その成果物を捨てることになる
if grep -qx "build" "$WORK/nix.calls" 2>/dev/null; then
  ng "照合が落ちたら、全ホストの検証のビルドを始めない"
else
  ok "照合が落ちたら、全ホストの検証のビルドを始めない"
fi

printf '#!/usr/bin/env bash\nexit 0\n' > "$CONTRACT"
bash "$SCRIPT" update >"$WORK/out" 2>&1 || true
if grep -q "stub sudo called" "$WORK/out"; then
  ok "照合が通れば切り替えに進む"
else
  ng "照合が通れば切り替えに進む"
fi

echo "==> rebuild は、main にいれば origin/main の全体を取り込んでからビルドする"
# flake.lock だけを取り込むと、origin でモジュールと lock が一緒に変わったとき、新しい lock と古いモジュールという、
# どこでも検証していない組み合わせをビルドする
printf '#!/bin/sh\necho "stub sudo called" >&2\nexit 1\n' > "$WORK/bin/sudo"
rm -f "$CONTRACT"
git -C "$REPO" checkout -q HEAD -- . 2>/dev/null || true
git -C "$REPO" switch -q main
git -C "$REPO" pull -q --ff-only origin main
# other: origin/main を 1 コミット進める（モジュールと lock を一緒に変える）
advance_origin() {
  git -C "$WORK/other" pull -q --ff-only origin main
  echo "$1" > "$WORK/other/module.nix"
  echo "{\"lock\":\"$1\"}" > "$WORK/other/flake.lock"
  git -C "$WORK/other" add module.nix flake.lock
  git -C "$WORK/other" commit -qm "feat: $1"
  git -C "$WORK/other" push -q origin main
}
advance_origin m1
bash "$SCRIPT" rebuild >"$WORK/out" 2>&1 || true
if [[ "$(cat "$REPO/module.nix" 2>/dev/null)" == "m1" && "$(cat "$REPO/flake.lock")" == '{"lock":"m1"}' ]] \
  && [[ "$(git -C "$REPO" rev-parse HEAD)" == "$(git -C "$REPO" rev-parse origin/main)" ]] \
  && [[ -z "$(git -C "$REPO" status --porcelain)" ]]; then
  ok "main を origin/main まで進め、モジュールも lock も取り込み、作業ツリーを汚さない"
else
  ng "main を origin/main まで進め、モジュールも lock も取り込み、作業ツリーを汚さない"
fi
if grep -q "stub sudo called" "$WORK/out"; then ok "取り込んだ後にビルドに進む"; else ng "取り込んだ後にビルドに進む"; fi

# 前の rebuild が残した状態（origin の lock をステージしただけで、HEAD は遅れている）からも進める
advance_origin m2
git -C "$REPO" fetch -q origin main
git -C "$REPO" checkout -q origin/main -- flake.lock
bash "$SCRIPT" rebuild >"$WORK/out" 2>&1 || true
if [[ "$(cat "$REPO/module.nix")" == "m2" && -z "$(git -C "$REPO" status --porcelain)" ]]; then
  ok "origin の lock をステージしただけの状態からも、全体を取り込む"
else
  ng "origin の lock をステージしただけの状態からも、全体を取り込む"
fi

echo "==> rebuild は、main 以外のブランチでは取り込まず、そのブランチをビルドする"
# sudoers が --flake を ~/nix/nixfiles に固定しているので、ブランチの変更を試すにはここで checkout する
advance_origin m3
git -C "$REPO" switch -q feat/x
before=$(git -C "$REPO" rev-parse HEAD)
bash "$SCRIPT" rebuild >"$WORK/out" 2>&1 || true
if [[ "$(git -C "$REPO" rev-parse HEAD)" == "$before" && -z "$(git -C "$REPO" status --porcelain)" ]]; then
  ok "ブランチを動かさず、lock も書き換えない"
else
  ng "ブランチを動かさず、lock も書き換えない"
fi
if grep -q "feat/x" "$WORK/out" && grep -q "stub sudo called" "$WORK/out"; then
  ok "ブランチの名前を出して、そのままビルドに進む"
else
  ng "ブランチの名前を出して、そのままビルドに進む"
fi

echo "==> rebuild は、main を origin/main まで進められなければ、ビルドせずに止まる"
git -C "$REPO" switch -q main
echo local > "$REPO/local.nix"
git -C "$REPO" add local.nix
git -C "$REPO" commit -qm "feat: local"
if bash "$SCRIPT" rebuild >"$WORK/out" 2>&1; then
  ng "履歴が分かれていれば失敗終了する"
elif grep -q "stub sudo called" "$WORK/out"; then
  ng "履歴が分かれていればビルドしない"
else
  ok "履歴が分かれていれば、ビルドせずに失敗終了する"
fi
git -C "$REPO" reset -q --hard origin/main

echo "==> rebuild は、origin に届かなければ、警告して手元の中身でビルドする"
git -C "$REPO" remote set-url origin "$WORK/no-such-origin.git"
bash "$SCRIPT" rebuild >"$WORK/out" 2>&1 || true
if grep -q "stub sudo called" "$WORK/out" && grep -q "origin に届かない" "$WORK/out"; then
  ok "origin に届かないことを知らせて、ビルドに進む"
else
  ng "origin に届かないことを知らせて、ビルドに進む"
fi
git -C "$REPO" remote set-url origin "$WORK/origin.git"

echo
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
