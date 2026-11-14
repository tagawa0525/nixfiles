#!/usr/bin/env bash
# =============================================================================
# このリポジトリの構成とスクリプトが、ハーネス（flake input の claude-harness）との約束を守っていることを検証する
# =============================================================================
# ハーネスのスクリプトと hook は、このリポジトリの名前や値を約束として固定で持つ。片方だけ変えると、どちらの
# リポジトリのテストも通ったまま食い違うので、構成とスクリプトを持つこちらで照合する。ハーネスの側は、本文を読まず、
# lock の版を偽物の下か一時のリポジトリで動かして見る（本文の書き方や、中身を claude-hooks に移す直しで落ちないように）。
#
#   1. 自動コミットするスクリプトの件名が、ハーネスの commit-msg hook を通る
#      （実際に起きた不整合: nix-rebuild.sh が `flake: update (host)` を書き、hook の型の一覧に flake が無かったので、
#      Claude Code のセッションからの update が最後のコミットで必ず失敗した）
#   2. Slurm のパーティションの名前、NFS の入口、終わったジョブの記録の置き場で、ハーネスの slurm-run.sh と
#      slurm-history.sh が動く
#   3. ハーネスの post-merge-cleanup が、こちらの nix-rebuild.sh を「rebuild する構成のリポジトリ」の目印にして、マージの
#      後に rebuild を知らせる
#   4. nix-rebuild.sh が main に直接コミットするのは flake.lock だけ（hook の main への直接コミットの例外。hook の側の
#      例外は、ハーネスの main-commit-gates.sh が確かめる）
#
# 照合しない約束: ハーネスの hook が rebuild として見るコマンドの名前（modules/home/parts/shell.nix の関数 rebuild と
# update、スクリプト nix-rebuild）。PreToolUse の hook に Claude Code の入力を作って渡せば動かして確かめられるが、
# まだ書いていない（#690）。このスクリプトは毎日の自動更新を止めるので、挙動が変わらない直しで止まる照合（ソースの本文の
# 照合）は入れない（試して捨てた照合は ADR-0082 の補足 2026-11-14）
#
# 使い方（リポジトリルートで実行）:
#   ./modules/home/parts/tests/harness-contract.sh [host]
#
# 呼ばれる場所:
#   - nix-rebuild.sh の update が、lock を進めた後、検証のビルドと切り替えの前に呼ぶ（毎日の自動更新でも走る）
#   - .pre-commit-config.yaml が、約束に関わるファイルを変えるコミットで呼ぶ

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
# pre-commit から呼ばれると、git が GIT_DIR や GIT_INDEX_FILE を渡す。残したままだと、下の一時のリポジトリの git init が
# 新しいリポジトリを作らず、commit-msg hook がコミット中のリポジトリを相手に動く
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR

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
# ハーネスのスクリプトの本文でなく、偽の sbatch などの下で動かして、渡す値を見る（本文の書き方や、中身を claude-hooks に
# 移す直しで落ちないように）
echo "==> Slurm の構成（modules/slurm/）でハーネスのスクリプトを動かす"
RUN="$HARNESS/.claude/scripts/slurm-run.sh"
HISTORY="$HARNESS/.claude/scripts/slurm-history.sh"

# 見つからないときは空にして、下の ✗ で知らせる（set -e と pipefail で、何も出さずに止まらないように）
protected=$(grep -o '"[a-z0-9]* Nodes=[^"]*PreemptMode=OFF' modules/slurm/common.nix | cut -d' ' -f1 | tr -d '"' || true)
default=$(grep -o '"[a-z0-9]* Nodes=[^"]*Default=YES' modules/slurm/common.nix | cut -d' ' -f1 | tr -d '"' || true)
entry=$(grep -o '^"[^"]*"$' modules/slurm/nfs-entry.nix | tr -d '"' || true)
jobcomp=$(grep -o 'JobCompLoc=[^ ]*' modules/slurm/common.nix | cut -d= -f2 || true)

# sbatch は引数を記録して番号を出し、ジョブを 0 で終える。scontrol show は終わったジョブを、squeue は空の待ち行列を返す。
# hostname は FAKE_HOST
SLURM_BIN="$WORK/slurm-bin"
mkdir -p "$SLURM_BIN"
cat >"$SLURM_BIN/sbatch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_SLURM/sbatch.args"
echo "Submitted batch job 42"
EOF
cat >"$SLURM_BIN/scontrol" <<'EOF'
#!/usr/bin/env bash
[[ $1 == show ]] && echo "JobId=42 RunTime=00:00:01 TimeLimit=00:01:00 SuspendTime=None Partition=x"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$SLURM_BIN/squeue"
printf '#!/usr/bin/env bash\necho "$FAKE_HOST"\n' >"$SLURM_BIN/hostname"
chmod +x "$SLURM_BIN"/*
mkdir -p "$WORK/home/github/contract"

# submit <host> <cwd> <slurm-run.sh の引数…>: 偽物の下で slurm-run.sh を投げ、標準エラーを $WORK/slurm.err に残す
submit() {
  local host=$1 dir=$2
  shift 2
  rm -f "$WORK/sbatch.args"
  (cd "$dir" && env -u SLURM_RUN_NFS_ENTRY -u CLAUDE_CODE_SESSION_ID HOME="$WORK/home" PATH="$SLURM_BIN:$PATH" \
    FAKE_HOST="$host" FAKE_SLURM="$WORK" timeout 60 "$RUN" --ref '#0' --purpose 'ハーネスとの約束の確認' -t 1 "$@" contract true) \
    >/dev/null 2>"$WORK/slurm.err" || true
}

submit r995 "$WORK/home/github/contract" --class timed
if [[ -n "$protected" ]] && grep -qxF -- "--partition=$protected" "$WORK/sbatch.args" 2>/dev/null; then
  ok "割り込まれないパーティション（$protected）に、slurm-run.sh が時間を記録するジョブを投げる"
else
  ng "割り込まれないパーティション（'$protected'）に、slurm-run.sh --class timed が投げない: $(cat "$WORK/slurm.err")"
fi
submit r995 "$WORK/home/github/contract" --class trial
if [[ -n "$default" ]] && grep -qxF -- "--partition=$default" "$WORK/sbatch.args" 2>/dev/null; then
  ok "既定のパーティション（$default）を、slurm-run.sh が明示して投げる"
else
  ng "既定のパーティション（'$default'）を、slurm-run.sh が明示して投げない: $(cat "$WORK/slurm.err")"
fi
# r995 の外で、入口の外から投げると、既定の入口の下で投げるよう求めて止まる
submit t14g4 "$WORK" --class trial
if [[ -n "$entry" ]] && [[ ! -e "$WORK/sbatch.args" ]] && grep -qF -- " $entry の下で" "$WORK/slurm.err"; then
  ok "NFS の入口（$entry）が、slurm-run.sh の既定の入口と同じ"
else
  ng "NFS の入口（'$entry'）が slurm-run.sh の既定の入口と違う: $(cat "$WORK/slurm.err")"
fi

# jobcomp の 1 件（slurm-history.sh が読む形）。時刻は、ハーネスが割り込みを数え始める時刻を後へ動かしても越えない先に置く
job() {
  printf 'JobId=%s UserId=u(1000) GroupId=g(100) Name=%s JobState=COMPLETED Partition=%s TimeLimit=10 StartTime=2099-01-01T10:00:00 EndTime=2099-01-01T10:05:00 NodeList=r995 NodeCnt=1 ProcCnt=32 WorkDir=/w\n' "$@"
}
{
  job 1 contract-protected "$protected"
  job 2 contract-other "$protected-other"
} >"$WORK/job_completions"
history_out=$(timeout 60 "$HISTORY" "$WORK/job_completions" 2>&1 || true)
if [[ -n "$protected" ]] && grep -qF contract-protected <<<"$history_out" && ! grep -qF contract-other <<<"$history_out"; then
  ok "割り込まれないパーティション（$protected）のジョブを、slurm-history.sh が表に入れる"
else
  ng "割り込まれないパーティション（'$protected'）のジョブだけを slurm-history.sh が表に入れない: $history_out"
fi
# 既定のファイルは、読めるホスト（r995）では、引数なしの出力が $jobcomp を渡したときと同じかを見る（間に slurmctld が
# 書き足せば違うので、1 度だけやり直す）。読めないホストでは、読めないと止まる案内のパスを見る
history_same() {
  local a b
  a=$(timeout 60 "$HISTORY" 2>&1; echo "exit=$?")
  b=$(timeout 60 "$HISTORY" "$jobcomp" 2>&1; echo "exit=$?")
  [[ "$a" == "$b" ]]
}
if [[ -n "$jobcomp" && -r "$jobcomp" ]]; then
  if history_same || history_same; then
    ok "終わったジョブの記録の置き場（$jobcomp）を、slurm-history.sh が既定で読む"
  else
    ng "slurm-history.sh の既定のファイルが、終わったジョブの記録の置き場（'$jobcomp'）と違う（引数なしと出力が違う）"
  fi
elif history_err=$(timeout 60 "$HISTORY" 2>&1 >/dev/null); then
  ng "slurm-history.sh が既定のファイルを読んで終わったが、'$jobcomp' はこのホストで読めない（別の既定を読んだ）"
elif [[ -n "$jobcomp" && "$history_err" == *": $jobcomp" ]]; then
  ok "終わったジョブの記録の置き場（$jobcomp）が、slurm-history.sh の既定のファイルと同じ"
else
  ng "終わったジョブの記録の置き場（'$jobcomp'）が slurm-history.sh の既定のファイルと違う: $history_err"
fi

# --- 3. rebuild する構成のリポジトリの目印 ------------------------------------------------------------
# lock の版の claude-hooks の post-merge-cleanup を、目印のあるリポジトリとないリポジトリで動かし、hosts/ を変えた
# マージの後に rebuild を知らせるのが、目印のあるほうだけかを見る。リモートは手元のパスで、gh は PATH に置かない
echo "==> post-merge-cleanup を一時のリポジトリで動かす"
MARKER=modules/home/scripts/nix-rebuild.sh
# 配置の source は「<パッケージ>/bin/claude-hooks」の文字列で、nix build に渡せないので、文字列の元の derivation を作る
HOOKS_DRV=$(nix eval --raw --impure --option warn-dirty false --expr "builtins.head (builtins.attrNames (builtins.getContext
  (builtins.getFlake \"git+file://$ROOT\").nixosConfigurations.${HOST}.config.home-manager.users.tagawa.home.file.\".claude/bin/claude-hooks\".source))")
HOOKS="$(nix build --no-link --print-out-paths --option warn-dirty false "$HOOKS_DRV^out")/bin/claude-hooks"
GIT_BIN="$WORK/git-bin"
mkdir -p "$GIT_BIN"
# 包むスクリプトでなく本体を置く（PATH はこれだけなので、#! の bash や env を引けない）
ln -s "$(readlink -f "$(command -v git)")" "$GIT_BIN/git"
# cleanup_note <名前> <目印のパス | 空>: 一時のリポジトリを作り、post-merge-cleanup の出力を返す。git はすべて -C で
# 一時のリポジトリに向け、作れなければ動かさない（呼ぶ側は || true なので set -e が効かず、cd の失敗の後の手順が
# このリポジトリで走ってしまう）
cleanup_note() {
  local marker=$2 r="$WORK/cleanup-$1"
  local repo="$r/repo"
  (
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=c GIT_AUTHOR_EMAIL=c@example.com \
      GIT_COMMITTER_NAME=c GIT_COMMITTER_EMAIL=c@example.com
    git init -q --bare -b main "$r/origin.git" &&
      git init -q -b main "$repo" && git -C "$repo" remote add origin "$r/origin.git" &&
      mkdir -p "$repo/$(dirname "${marker:-README}")" && touch "$repo/${marker:-README}" &&
      git -C "$repo" add -A && git -C "$repo" commit -q -m init && git -C "$repo" push -q -u origin main &&
      git -C "$repo" switch -q -c feat && mkdir "$repo/hosts" && touch "$repo/hosts/x" &&
      git -C "$repo" add hosts && git -C "$repo" commit -q -m feat && git -C "$repo" push -q origin feat:main &&
      git -C "$repo" switch -q main || { echo "一時のリポジトリを作れない: $repo"; exit 1; }
    cd "$repo" || exit 1
    timeout 60 env PATH="$GIT_BIN" "$HOOKS" script post-merge-cleanup feat 2>&1
  ) || true
}
with=$(cleanup_note with "$MARKER")
without=$(cleanup_note without "")
# 目印の無いほうも、知らせを出す前の手順（ブランチの削除）まで進んだことを確かめてから、知らせが無いことを見る
if [[ -f "$MARKER" ]] && grep -q '^NOTE: rebuild' <<<"$with" && grep -q '^LOCAL_BRANCH: deleted' <<<"$without" &&
  ! grep -q '^NOTE: rebuild' <<<"$without"; then
  ok "post-merge-cleanup が $MARKER を目印に、マージの後に rebuild を知らせる"
else
  ng "$MARKER が無いか、post-merge-cleanup がそれを目印に rebuild を知らせない:
目印あり: $with
目印なし: $without"
fi

# --- 4. main に直接コミットするのは flake.lock だけ ---------------------------------------------------
echo "==> nix-rebuild.sh がステージするファイルを確かめる"
# hook は、既定ブランチへの直接のコミットを、ステージした変更が flake.lock だけのときに限って通す
added=$(grep -oE 'git add [^;&|]*' "$MARKER" | sort -u || true)
if [[ "$added" == "git add flake.lock" ]]; then
  ok "nix-rebuild.sh がステージするのは flake.lock だけ"
else
  ng "nix-rebuild.sh が flake.lock のほかもステージする（main への直接のコミットを hook が止める）: $added"
fi

echo
echo "passed: $PASS, failed: $FAIL"
((FAIL == 0))
