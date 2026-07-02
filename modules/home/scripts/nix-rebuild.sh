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
  nix flake update
  echo "🔨 Rebuilding NixOS..."
  if ! sudo nixos-rebuild switch --flake .; then
    echo "❌ Rebuild failed, not pushing changes"
    cd - > /dev/null
    return 1
  fi
  # 変更がある場合のみコミット＆プッシュ
  if ! git diff --quiet flake.lock 2>/dev/null; then
    echo "📤 Committing and pushing flake.lock..."
    git add flake.lock
    git commit -m "flake: update ($HOSTNAME)"
    # プッシュ失敗時は一度だけリトライ
    if ! git push; then
      echo "⚠️  Push failed, pulling and retrying..."
      if git pull --rebase origin main && git push; then
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
