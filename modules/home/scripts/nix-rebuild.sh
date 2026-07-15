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
  sudo nixos-rebuild switch --flake .
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
  if ! nix build --no-link "${targets[@]}"; then
    echo "❌ Verification failed for some hosts, not switching or pushing"
    reset_lock
    cd - > /dev/null
    return 1
  fi
  echo "🔨 Rebuilding NixOS..."
  # コマンドのフルパスと --flake の絶対パスは modules/nix-auto-update.nix の
  # NOPASSWD ルール（コマンド行の完全一致）に合わせるため。PATH 解決に
  # 依存すると sudoers と不一致になり、user service ではパスワード入力
  # できず失敗する。動作は sudo nixos-rebuild switch --flake . と同じ
  if ! sudo /run/current-system/sw/bin/nixos-rebuild switch --flake "$NIXDIR"; then
    echo "❌ Rebuild failed, not pushing changes"
    reset_lock
    cd - > /dev/null
    return 1
  fi
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
