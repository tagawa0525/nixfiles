#!/usr/bin/env bash
# =============================================================================
# NixOS Rebuild Helper
# =============================================================================
# リモートのflake.lockを取得してからNixOSを再構築
# Usage: nix-rebuild.sh rebuild
#        nix-rebuild.sh update

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
nixos_rebuild_switch() {
  sudo /run/current-system/sw/bin/nixos-rebuild switch --flake "$NIXDIR"
}

rebuild() {
  cd "$NIXDIR" || return 1
  echo "📥 Pulling latest changes from remote..."
  # flake.lockのみをpull（他のファイルに影響しない）
  git fetch origin main
  if git diff --quiet flake.lock 2>/dev/null; then
    # ローカルに変更がない場合のみリモート版を取得
    git checkout origin/main -- flake.lock 2>/dev/null || echo "ℹ️  No remote changes to flake.lock"
  else
    echo "⚠️  Local changes detected in flake.lock"
    echo "   Run 'git diff flake.lock' to review changes"
    echo "   Consider running 'update' instead to sync properly"
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
  echo "⬆️  Updating flake..."
  # set -e による即終了を避けて明示ハンドリングする（部分的に書き換わった
  # flake.lock が残ると翌日以降の git pull --rebase が詰まるため）
  if ! nix flake update; then
    echo "❌ Flake update failed"
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
    git commit -m "flake: update ($HOSTNAME)"
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

# メイン処理
case "${1:-}" in
  rebuild)
    rebuild
    ;;
  update)
    update
    ;;
  *)
    echo "Usage: $0 {rebuild|update}"
    exit 1
    ;;
esac
