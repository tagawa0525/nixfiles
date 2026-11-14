#!/usr/bin/env bash
# =============================================================================
# NixOS Rebuild Helper
# =============================================================================
# origin/main を取り込んでから NixOS を再構築
# Usage: nix-rebuild.sh rebuild            main にいれば origin/main まで進めてからビルドする。ほかのブランチはそのままビルドする
#        nix-rebuild.sh update [input...]   input を挙げると、その input だけを進める（例: update claude-harness）
#        --local（rebuild か update の後に付ける）: ラップトップでも r995 に投げず、手元でビルドする。既定は r995 に
#        投げる（速い）。r995 が時間を記録する Slurm のジョブを実行している間に、その時間を乱さずにビルドするための逃げ道

set -e

NIXDIR=~/nix/nixfiles
HOSTNAME=$(hostname)
# 検証ビルドの成果物に張る GC ルートの置き場。home-manager の
# ~/.local/state/home-manager/gcroots に倣う（cache ではなく state）
GCROOTS=~/.local/state/nix-rebuild/gcroots

# switch は必ずこの関数を経由する。sudoers の NOPASSWD ルール
# （modules/nix-rebuild-nopasswd.nix）はコマンド行の完全一致で許可を判定するため、
# コマンドのフルパスと --flake の絶対パスをここ 1 箇所に集約して、sudoers と
# 食い違わないようにする。PATH 解決や `--flake .` に依存すると sudoers と
# 一致せず、パスワードを入力できない user service（自動更新）で失敗する。
#
# `--flake .` を許可しない理由: sudo は cwd を制約できないため、`.` を許した
# ルールは「任意のディレクトリに置いた flake をパスワードなしで root 適用
# できる」ことと等価になり、コマンド行を固定した意味が失われる。
#
# --local の switch は、root の nixos-rebuild が /etc/nix のリモートのビルダー（r995）を使わず手元でビルドするよう、
# 固定した 2 つ目のコマンド行で呼ぶ（sudoers の 2 つ目のルール）。`--builders ""` の空の引数は sudoers の完全一致で
# 「引数なし」と紛れるので、空のファイルを読ませる `@/dev/null` で外す（捨てた方式は #692）
nixos_rebuild_switch() {
  if [[ -n "$LOCAL" ]]; then
    sudo /run/current-system/sw/bin/nixos-rebuild switch --flake "$NIXDIR" --builders @/dev/null --max-jobs auto
  else
    sudo /run/current-system/sw/bin/nixos-rebuild switch --flake "$NIXDIR"
  fi
}

rebuild() {
  cd "$NIXDIR" || return 1
  # main にいれば、origin/main の全体を取り込んでからビルドする。flake.lock だけを取り込むと、origin でモジュールと
  # lock が一緒に変わったとき、新しい lock と古いモジュールという、どこでも検証していない組み合わせをビルドする
  local branch
  branch=$(git symbolic-ref --short -q HEAD || echo "detached HEAD")
  if [[ "$branch" != main ]]; then
    # sudoers が --flake をこのディレクトリに固定しているので、ブランチの変更を試すにはここで checkout する
    # （ブランチがほかの worktree にあれば git switch --detach <ブランチ>）。そのときは取り込まず、そのままビルドする
    echo "ℹ️  $branch（$(git rev-parse --short HEAD)）をそのままビルドします（origin/main を取り込むのは、main にいるときだけ）"
    echo "   試した後は main に戻してください（main 以外では、毎朝の自動更新が失敗します）"
  else
    echo "📥 Pulling latest changes from remote..."
    # 届かない、認証の失敗、URL の誤りのどれでも、origin の最新を確かめられない。手元の中身でビルドすると、
    # マージした変更が入らないまま成功に見えるので止める
    if ! git fetch origin main; then
      echo "❌ git fetch に失敗しました（上の出力を参照）。origin の最新を確かめられないので、ビルドしません"
      echo "   手元の中身でビルドするなら: git -C $NIXDIR switch --detach のあと rebuild（終わったら git switch main）"
      cd - > /dev/null
      return 1
    fi
    # コミットされていない変更は捨てない（走っている update の書きかけや、手で進めて試している lock でありうる）。
    # origin の変更と重ならなければ残したまま進み、重なれば git が何も変えずに止める
    # origin に無い手元のコミット。origin/main の ref が無い clone では空として扱う（下の merge が理由を出して止まる）
    local ahead line
    ahead=$(git log --oneline origin/main..main 2> /dev/null) || ahead=
    if ! git merge --ff-only origin/main; then
      echo "❌ main を origin/main まで進められません（上の git の出力を参照）。ビルドしません"
      if [[ -n "$ahead" ]]; then
        echo "   origin に無い手元のコミットがあり、履歴が分かれています（git log --oneline origin/main..main）:"
        while IFS= read -r line; do echo "     $line"; done <<< "$ahead"
        echo "   flake.lock の更新だけなら、nix-rebuild update で origin に合わせられます"
      else
        echo "   手元の状態（git status --short）:"
        git status --short | sed 's/^/     /'
        if [[ -n "$(git status --porcelain -- flake.lock)" ]]; then
          echo "   手元の flake.lock を捨てて origin に合わせるなら: git -C $NIXDIR restore --staged --worktree flake.lock"
        fi
      fi
      cd - > /dev/null
      return 1
    fi
    if [[ -n "$ahead" ]]; then
      echo "ℹ️  origin に無いコミットを含めてビルドします（push していない手元のコミット）:"
      while IFS= read -r line; do echo "     $line"; done <<< "$ahead"
    fi
  fi
  echo "🔨 Rebuilding NixOS..."
  nixos_rebuild_switch
  cd - > /dev/null
}

# 失敗時に flake.lock を元に戻す。dirty な flake.lock が残ると翌日以降の
# git pull --rebase が失敗し続け、自動更新 (modules/nix-auto-update.nix) が
# 詰まるため。失敗した lock は nix flake update で再現できるので情報は失わない
reset_lock() {
  echo "↩️  Resetting flake.lock (reproduce with: nix flake update)"
  # HEAD 指定で index / worktree の両方を復元する（-- のみだと index からの
  # 復元になり、staged だった場合に dirty が残るため）
  git checkout HEAD -- flake.lock
}

# 検証済み toplevel に GC ルートを張る。
#
# ルートが無いと自ホスト以外の成果物（自ホスト分は /run/current-system が
# 守る）は常に GC 対象で、週次 GC（modules/profiles/base.nix の nix.gc）の
# たびに消える。消えるのは systemd unit / etc / fish-completions といった
# ホスト固有の生成物で、そのホスト構成でしか作られないためバイナリキャッシュ
# に存在せず、次回の検証で必ずローカルビルドし直しになる。
# r995 はラップトップのリモートビルダーも兼ねるので、ここを残しておくと
# 同じ lock で update してくる他ホストの再ビルドも省ける。
#
# ルート張りの失敗は「次回のビルドキャッシュが効かない」だけで update 自体は
# 成功しているため、呼び出し側で `|| true` を付けて set -e による中断を止め、
# 内部でも警告に留める。ここで死ぬと flake.lock が dirty のまま残り、翌日
# 以降の git pull --rebase が詰まる（reset_lock のコメント参照）。
# 第1引数は nix build --print-out-paths の出力、第2引数以降がホスト名。
add_gcroots() {
  local built=$1
  shift
  local host_names=("$@")
  local paths link name h i
  mapfile -t paths <<< "$built"
  # 出力順が installable の指定順と 1:1 対応することに依存するため、件数が
  # 食い違ったら黙って取り違えるより何もしない方が安全（nix は重複した
  # installable を渡すと出力行が増える）
  if [[ ${#paths[@]} -ne ${#host_names[@]} ]]; then
    echo "⚠️  出力パス数 ${#paths[@]} がホスト数 ${#host_names[@]} と一致しません。GC ルートをスキップします"
    return 0
  fi
  mkdir -p "$GCROOTS"
  # 先に張り替えてから不要な名前を掃除する。逆順にすると全削除から再作成
  # までの間に GC が走ったとき、全ホストが無ルートで削除されうる
  for i in "${!host_names[@]}"; do
    nix-store --realise "${paths[i]}" --add-root "$GCROOTS/${host_names[i]}" > /dev/null \
      || echo "⚠️  ${host_names[i]} の GC ルートを張れませんでした"
  done
  # hosts/ から消えたホストのルートが古い closure を pin し続けるのを防ぐ
  for link in "$GCROOTS"/*; do
    [[ -L $link ]] || continue
    name=$(basename "$link")
    for h in "${host_names[@]}"; do
      [[ $h == "$name" ]] && continue 2
    done
    rm -f "$link"
  done
}

update() {
  cd "$NIXDIR" || return 1
  # update は origin/main を取り込んで main に lock を push する処理。feature branch
  # で走ると、そのブランチが main 上へリベースされ、lock のコミットが PR に積まれて
  # push される（PR #239）。何かを変える前に止める
  local branch
  branch=$(git symbolic-ref --short -q HEAD || echo "detached HEAD")
  if [[ "$branch" != main ]]; then
    echo "❌ update は main ブランチで実行してください（現在: $branch）"
    cd - > /dev/null
    return 1
  fi
  echo "📥 Syncing with remote..."
  git fetch origin main
  # flake.lock以外にローカル変更がある場合は警告
  if ! git diff --quiet --diff-filter=M -- . ':!flake.lock' 2>/dev/null; then
    echo "⚠️  Warning: You have local changes besides flake.lock"
    git status --short
  fi
  # リモートの変更を取り込む（rebaseでflake.lockの競合を回避）
  if ! git pull --rebase origin main; then
    conflicts=$(git diff --name-only --diff-filter=U)
    if [[ "$conflicts" != "flake.lock" ]]; then
      echo "❌ Pull failed (flake.lock 単独の競合ではありません)"
      echo "   手動で解決してください: git status"
      git rebase --abort 2>/dev/null || true
      cd - > /dev/null
      return 1
    fi
    echo "⚠️  flake.lock が競合しました。リモート版を優先して解決します..."
    # rebase 中は ours=リベース先(origin/main)、theirs=ローカル側のコミット
    git checkout --ours -- flake.lock
    git add flake.lock
    # ローカルコミットが flake.lock のみだった場合、リモート版採用で
    # 空コミットになり --continue が失敗するため --skip にフォールバック
    if ! GIT_EDITOR=true git rebase --continue && ! git rebase --skip; then
      echo "❌ Rebase を継続できませんでした。中断して元の状態に戻します"
      git rebase --abort
      cd - > /dev/null
      return 1
    fi
  fi
  # nix flake update は、flake に無い input の名前を警告だけで通す（終了コード 0）。打ち間違いのまま検証と切り替えまで
  # 進むと、直しが入っていないのに成功に見えるので、進める lock（pull の後）の input の名前と照らす。
  # 引数の無い経路（毎朝の自動更新）は、jq と lock の形に頼らせない
  if (($# > 0)); then
    local known input
    if ! known=$(jq -r '.nodes.root.inputs | keys[]' flake.lock); then
      echo "❌ flake.lock の input の名前を読めません"
      cd - > /dev/null
      return 1
    fi
    for input in "$@"; do
      if [[ -z "$input" ]] || ! grep -qxF -- "$input" <<< "$known"; then
        echo "❌ flake に無い input です: $input"
        echo "   使える名前: ${known//$'\n'/ }"
        cd - > /dev/null
        return 1
      fi
    done
  fi
  echo "⬆️  Updating flake..."
  # set -e による即終了を避けて明示ハンドリングする（部分的に書き換わった
  # flake.lock が残ると翌日以降の git pull --rebase が詰まるため）
  # input を挙げたときは、それだけを進める。ハーネス（claude-harness）の直しを、その日の nixpkgs のビルドの失敗に
  # 巻き込まれずに反映するため
  if ! nix flake update "$@"; then
    echo "❌ Flake update failed"
    reset_lock
    cd - > /dev/null
    return 1
  fi
  # ハーネス（flake input の claude-harness）のスクリプトが固定で持つ名前と値が、この構成と合っていることを確かめる。
  # ハーネスの lock を進めた版が約束を変えていたら、切り替える前に止める（照合する中身はスクリプトの冒頭）。
  # ビルドするのは commit-msg の hook と claude-hooks だけなので、全ホストのビルドの前に置く。hook を取り出すために、
  # 進めた lock でこのホストの構成を評価するので、新しい nixpkgs で評価できないときもここで止まる
  contract="$NIXDIR/modules/home/parts/tests/harness-contract.sh"
  echo "🤝 Checking the contract with claude-harness..."
  if ! bash "$contract" "$HOSTNAME"; then
    echo "❌ Harness contract check failed (or this host no longer evaluates with the new lock), not switching or pushing"
    reset_lock
    cd - > /dev/null
    return 1
  fi
  echo "🧪 Verifying all host configurations..."
  # 未検証の flake.lock を main に push しないための必須ゲート。
  # ラップトップでは nix-distributed-builds により実ビルドは r995 で走る
  # （評価と成果物の転送のみローカル）。r995 に到達できない場合はここで
  # 失敗し、push されない。
  if ! hosts=$(nix eval .#nixosConfigurations --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)' --raw); then
    echo "❌ Failed to enumerate hosts, not switching or pushing"
    reset_lock
    cd - > /dev/null
    return 1
  fi
  read -ra host_list <<< "$hosts"
  targets=()
  for h in "${host_list[@]}"; do
    targets+=(".#nixosConfigurations.${h}.config.system.build.toplevel")
  done
  if ! built=$(nix build --no-link --print-out-paths "${targets[@]}"); then
    echo "❌ Verification failed for some hosts, not switching or pushing"
    reset_lock
    cd - > /dev/null
    return 1
  fi
  echo "🔨 Rebuilding NixOS..."
  if ! nixos_rebuild_switch; then
    echo "❌ Rebuild failed, not pushing changes"
    reset_lock
    cd - > /dev/null
    return 1
  fi
  # switch 成功後に張る。失敗パスで張ってしまうと、reset_lock が戻した lock
  # 側の closure が無ルートになり、次回 GC で消えて全ホスト再ビルドになる
  add_gcroots "$built" "${host_list[@]}" || true
  # 変更がある場合のみコミット＆プッシュ
  if ! git diff --quiet flake.lock 2>/dev/null; then
    echo "📤 Committing and pushing flake.lock..."
    git add flake.lock
    # Conventional Commits（commit-msg hook が検証する）。`flake:` は型として無効で、
    # Claude Code セッションからの update が最後のコミットで必ず失敗していた
    git commit -m "chore(flake): update ($HOSTNAME)"
    # 検証済みの lock の内容を記録（リトライ時の変化検出に使う）
    lock_hash=$(git hash-object flake.lock)
    # プッシュ失敗時は一度だけリトライ
    if ! git push; then
      echo "⚠️  Push failed, pulling and retrying..."
      if ! git pull --rebase origin main; then
        echo "❌ Pull failed during retry. rebase を中断して戻します"
        git rebase --abort 2>/dev/null || true
        cd - > /dev/null
        return 1
      fi
      # rebase の textual merge で flake.lock が検証済みの内容から変わった
      # 場合は push しない（未検証の lock を main に載せないため）。
      # 次回の update で通常フローに合流して回復する
      if [[ "$(git hash-object flake.lock)" != "$lock_hash" ]]; then
        echo "❌ flake.lock が rebase で変化しました。再度 update を実行してください"
        cd - > /dev/null
        return 1
      fi
      if git push; then
        echo "✅ Successfully updated and pushed from $HOSTNAME"
      else
        echo "❌ Push failed again, please resolve manually"
        cd - > /dev/null
        return 1
      fi
    else
      echo "✅ Successfully updated and pushed from $HOSTNAME"
    fi
  else
    echo "ℹ️  No changes to commit"
  fi
  cd - > /dev/null
}

# rebuild と update を、同じ clone で同時に実行しない。実行中の update の検証の途中で HEAD や flake.lock を動かすと、
# 検証していない組み合わせに切り替わる。ロックのファイルは .git の中に置く（作業ツリーを汚さない）。
# ロックは flock のプロセスが持ち、このスクリプトを子として実行し直す。-o でロックの fd を子に継がせないので、子が後ろに
# 残したプロセス（git が切り離して起動する maintenance など）がロックを持ち続けない
exclusive() {
  [[ -z "${NIX_REBUILD_LOCKED:-}" ]] || return 0
  local gitdir rc=0
  if ! gitdir=$(git -C "$NIXDIR" rev-parse --absolute-git-dir); then
    echo "❌ $NIXDIR を git のリポジトリとして読めません"
    exit 1
  fi
  # 75 は、ロックを取れなかったときだけの終了コード（このスクリプト自身は 0 か 1 で終わる）
  NIX_REBUILD_LOCKED=1 flock -n -o -E 75 "$gitdir/nix-rebuild.lock" bash "$0" "$@" || rc=$?
  if ((rc == 75)); then
    echo "❌ ほかの nix-rebuild（rebuild か update。毎朝 06:30 の自動更新を含む）が実行中です。終わってから実行してください"
    exit 1
  fi
  exit "$rc"
}

# --local（サブコマンドの後）: 手元でビルドする。引数からだけ読む（環境から受けると、残った変数で毎朝の自動更新まで
# 手元でビルドしうる）。NIX_CONFIG で nix と、ハーネスとの約束の確認に渡す。ラップトップは r995 だけでビルドする
# 設定（max-jobs = 0）なので、手元のジョブも許す。NIX_CONFIG は wheel（trusted-users）のユーザーの設定として
# nix-daemon に渡る。switch の 2 つ目の sudoers の行は、それを入れた rebuild の後に効く（最初の 1 回は --local なしで入れる）
LOCAL=
ARGS=()
parse_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --local) LOCAL=1 ;;
      -*)
        echo "❌ 知らないオプションです: $arg"
        usage
        ;;
      *) ARGS+=("$arg") ;;
    esac
  done
  # Slurm の計算ノード（ラップトップのリモートのビルダー）かは、名前でなく scontrol で見る（scontrol が無いホストはノードでない）
  if [[ -n "$LOCAL" ]] && scontrol show node "$HOSTNAME" >/dev/null 2>&1; then
    echo "❌ 計算ノードの上では --local でもこのノードでビルドします（--local はラップトップで計算ノードに投げないための逃げ道）"
    exit 1
  fi
}

use_local_builds() {
  [[ -n "$LOCAL" ]] || return 0
  export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}builders =
max-jobs = auto"
}

usage() {
  echo "Usage: $0 {rebuild|update [input...]} [--local]"
  exit 1
}

# メイン処理。引数はロックを取る前に確かめる（誤りを、ほかの nix-rebuild の実行中の知らせに隠さない）
case "${1:-}" in
  rebuild)
    parse_args "${@:2}"
    ((${#ARGS[@]} == 0)) || usage
    exclusive "$@"
    use_local_builds
    rebuild
    ;;
  update)
    parse_args "${@:2}"
    exclusive "$@"
    use_local_builds
    update "${ARGS[@]}"
    ;;
  *)
    usage
    ;;
esac
