#!/usr/bin/env bash
# =============================================================================
# このリポジトリの構成とスクリプトが、ハーネス（flake input の claude-harness）との約束を守っていることを検証する
# =============================================================================
# ハーネスのスクリプトと hook は、このリポジトリの名前や値を約束として固定で持つ。片方だけ変えると、どちらの
# リポジトリのテストも通ったまま食い違うので、構成とスクリプトを持つこちらで突き合わせる。
#
#   1. 自動コミットするスクリプトの件名が、ハーネスの commit-msg hook を通る
#      （実際に起きた不整合: nix-rebuild.sh が `flake: update (host)` を書き、hook の型の一覧に flake が無かったので、
#      Claude Code のセッションからの update が最後のコミットで必ず失敗した）
#   2. Slurm のパーティションの名前、NFS の入口、終わったジョブの記録の置き場が、ハーネスの slurm-run.sh と
#      slurm-history.sh の値と同じ
#   3. ハーネスの post-merge-cleanup.sh が「rebuild する構成のリポジトリ」の目印にするファイルがある
#
# 使い方（リポジトリルートで実行）:
#   ./modules/home/parts/tests/harness-contract.sh [host]

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

HOST="${1:-r995}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "✓ $1"; }
ng() { FAIL=$((FAIL + 1)); echo "✗ $1" >&2; }

echo "==> ハーネスのソースを lock の版で取り出す"
HARNESS=$(nix eval --raw --impure --option warn-dirty false \
  --expr "(builtins.getFlake \"git+file://$ROOT\").inputs.claude-harness.outPath")
[[ -d "$HARNESS/.claude/scripts" ]] || { echo "✗ ハーネスのソースが読めない: $HARNESS" >&2; exit 1; }

# --- 1. 自動コミットするスクリプトの件名 -------------------------------------------------------------
echo "==> commit-msg hook をビルドする（nixosConfigurations.${HOST}）"
cp "$(nix build --no-link --print-out-paths --option warn-dirty false \
  ".#nixosConfigurations.${HOST}.config.home-manager.users.tagawa.xdg.configFile.\"git/hooks/commit-msg\".source")" \
  "$WORK/commit-msg"
chmod +x "$WORK/commit-msg"

# hook は Claude Code のセッションのコミットにだけ効く
export CLAUDECODE=1
# hook は git リポジトリの外だと何もせず exit 0 するので、一時のリポジトリの中で実行する
# （このリポジトリ自身の .git/hooks へ委譲されないよう、新しく init したものを使う）
git init -q "$WORK/repo"

# hook が件名を検査していることを先に確かめる（何でも通す状態だと、下の ✓ は何も確かめていない）
printf '%s\n' "flake: update (testhost)" > "$WORK/msg"
if (cd "$WORK/repo" && "$WORK/commit-msg" "$WORK/msg") >"$WORK/out" 2>&1; then
  ng "commit-msg hook が、型の一覧に無い件名（flake: update）を通した（検査が走っていない）"
else
  ok "commit-msg hook は、型の一覧に無い件名を止める"
fi

echo "==> スクリプトが書くメッセージを集めて hook に通す"
# `git commit -m "..."` の形で書かれたリテラルのメッセージを集める。変数の展開（$HOSTNAME など）は仮の値に置き換える
found=0
while IFS= read -r line; do
  msg=$(sed -E 's/.*git commit[^"]*"([^"]*)".*/\1/' <<<"$line")
  [[ -n "$msg" ]] || continue
  msg="${msg//\$HOSTNAME/testhost}"
  msg="${msg//\$\{HOSTNAME\}/testhost}"
  found=$((found + 1))
  printf '%s\n' "$msg" > "$WORK/msg"
  if (cd "$WORK/repo" && "$WORK/commit-msg" "$WORK/msg") >"$WORK/out" 2>&1; then
    ok "modules/home/scripts: $msg"
  else
    ng "modules/home/scripts の件名が commit-msg hook に止められる: $msg"
    sed 's/^/    /' "$WORK/out" >&2
  fi
done < <(grep -rhE 'git commit +-m +"[^"]+"' "$ROOT/modules/home/scripts" || true)
if ((found == 0)); then
  ng "スクリプトから git commit -m のメッセージを 1 件も集められなかった（書き方が変わったなら、集め方を見直す）"
fi

# --- 2. Slurm のパーティションの名前と NFS の入口 -----------------------------------------------------
echo "==> Slurm の構成（modules/slurm/）とハーネスのスクリプトを突き合わせる"
RUN="$HARNESS/.claude/scripts/slurm-run.sh"
HISTORY="$HARNESS/.claude/scripts/slurm-history.sh"

# 見つからないときは空にして、下の ✗ で知らせる（set -e と pipefail で、何も出さずに止まらないように）
protected=$(grep -o '"[a-z0-9]* Nodes=[^"]*PreemptMode=OFF' modules/slurm/common.nix | cut -d' ' -f1 | tr -d '"' || true)
default=$(grep -o '"[a-z0-9]* Nodes=[^"]*Default=YES' modules/slurm/common.nix | cut -d' ' -f1 | tr -d '"' || true)
entry=$(grep -o '^"[^"]*"$' modules/slurm/nfs-entry.nix | tr -d '"' || true)
jobcomp=$(grep -o 'JobCompLoc=[^ ]*' modules/slurm/common.nix | cut -d= -f2 || true)

if [[ -n "$protected" ]] && grep -qF -- "--partition=$protected" "$RUN"; then
  ok "割り込まれないパーティション（$protected）に、slurm-run.sh が時間を記録するジョブを投げる"
else
  ng "割り込まれないパーティション（'$protected'）が slurm-run.sh の --partition= に無い"
fi
if [[ -n "$protected" ]] && grep -qF "kv[\"Partition\"] != \"$protected\"" "$HISTORY"; then
  ok "割り込まれないパーティション（$protected）のジョブを、slurm-history.sh が表に入れる"
else
  ng "割り込まれないパーティション（'$protected'）が slurm-history.sh の判定に無い"
fi
if [[ -n "$default" ]] && grep -qF -- "--partition=$default" "$RUN"; then
  ok "既定のパーティション（$default）を、slurm-run.sh が明示して投げる"
else
  ng "既定のパーティション（'$default'）が slurm-run.sh の --partition= に無い"
fi
if [[ -n "$entry" && "$(grep -o 'SLURM_RUN_NFS_ENTRY:-[^}]*' "$RUN" | cut -d- -f2-)" == "$entry" ]]; then
  ok "NFS の入口（$entry）が、slurm-run.sh の既定の入口と同じ"
else
  ng "NFS の入口（'$entry'）が slurm-run.sh の既定の入口と違う"
fi
if [[ -n "$jobcomp" ]] && grep -qF "FILE=\"\${FILE:-$jobcomp}\"" "$HISTORY"; then
  ok "終わったジョブの記録の置き場（$jobcomp）が、slurm-history.sh の既定のファイルと同じ"
else
  ng "終わったジョブの記録の置き場（'$jobcomp'）が slurm-history.sh の既定のファイルと違う"
fi

# --- 3. rebuild する構成のリポジトリの目印 ------------------------------------------------------------
echo "==> post-merge-cleanup.sh の目印を確かめる"
MARKER=modules/home/scripts/nix-rebuild.sh
if [[ -f "$MARKER" ]] && grep -qF "HEAD:$MARKER" "$HARNESS/.claude/scripts/post-merge-cleanup.sh"; then
  ok "post-merge-cleanup.sh が目印にする $MARKER がある（マージの後に rebuild の知らせが出る）"
else
  ng "$MARKER が無いか、post-merge-cleanup.sh の目印と違う（マージの後に rebuild の知らせが出なくなる）"
fi

echo
echo "passed: $PASS, failed: $FAIL"
((FAIL == 0))
