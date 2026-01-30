# =============================================================================
# シェル関連の設定
# =============================================================================
# Fish, Starship, Zoxide, Direnv などシェル環境の設定
# デフォルトシェルはbash（tmux設定は tmux.nix を参照）
# =============================================================================

{
  # ===========================================================================
  # Fishシェル
  # ===========================================================================
  # モダンなシェル。強力な補完、シンタックスハイライト、履歴検索
  programs.fish = {
    enable = true;
    # 起動時のグリーティングメッセージを無効化
    interactiveShellInit = ''
      set -g fish_greeting
      # mise有効化（Fishシェルで自動補完とコマンドが使えるようになる）
      mise activate fish | source
    '';
    # よく使うコマンドのエイリアス
    shellAliases = {
      ls = "eza"; # モダンなls
      ll = "eza -la"; # 詳細表示
      la = "eza -a"; # 隠しファイル含む
      lt = "eza --tree"; # ツリー表示
      cat = "bat"; # シンタックスハイライト付きcat（programs.batで設定管理）
    };
    # NixOS再構築用コマンド（flake.lockの自動同期付き）
    functions = {
      # rebuild: リモートのflake.lockを取得してからrebuild
      rebuild = ''
        set -l nixdir ~/nix/nixfiles
        cd $nixdir
        echo "📥 Pulling latest changes from remote..."
        # flake.lockのみをpull（他のファイルに影響しない）
        git fetch origin main
        if git diff --quiet flake.lock 2>/dev/null
          # ローカルに変更がない場合のみリモート版を取得
          git checkout origin/main -- flake.lock 2>/dev/null
          or echo "ℹ️  No remote changes to flake.lock"
        else
          echo "⚠️  Local changes detected in flake.lock"
          echo "   Run 'git diff flake.lock' to review changes"
          echo "   Consider running 'update' instead to sync properly"
        end
        echo "🔨 Rebuilding NixOS..."
        sudo nixos-rebuild switch --flake .
        cd -
      '';
      # update: flake更新後に自動コミット＆プッシュ（競合時は自動リトライ）
      update = ''
        set -l nixdir ~/nix/nixfiles
        set -l hostname (hostname)
        cd $nixdir
        echo "📥 Syncing with remote..."
        git fetch origin main
        # flake.lock以外にローカル変更がある場合は警告
        if not git diff --quiet --diff-filter=M -- . ':!flake.lock' 2>/dev/null
          echo "⚠️  Warning: You have local changes besides flake.lock"
          git status --short
        end
        # リモートの変更を取り込む（rebaseでflake.lockの競合を回避）
        git pull --rebase origin main
        or begin
          echo "⚠️  Pull failed, attempting to resolve..."
          # flake.lockの競合はリモート版を優先
          if test -f flake.lock
            git checkout --theirs flake.lock 2>/dev/null
            git add flake.lock
            git rebase --continue 2>/dev/null
          end
        end
        echo "⬆️  Updating flake..."
        nix flake update
        echo "🔨 Rebuilding NixOS..."
        sudo nixos-rebuild switch --flake .
        or begin
          echo "❌ Rebuild failed, not pushing changes"
          cd -
          return 1
        end
        # 変更がある場合のみコミット＆プッシュ
        if not git diff --quiet flake.lock 2>/dev/null
          echo "📤 Committing and pushing flake.lock..."
          git add flake.lock
          git commit -m "flake: update ($hostname)"
          # プッシュ失敗時は一度だけリトライ
          if not git push
            echo "⚠️  Push failed, pulling and retrying..."
            git pull --rebase origin main
            and git push
            or begin
              echo "❌ Push failed again, please resolve manually"
              cd -
              return 1
            end
          end
          echo "✅ Successfully updated and pushed from $hostname"
        else
          echo "ℹ️  No changes to commit"
        end
        cd -
      '';
    };
  };

  # ===========================================================================
  # Starshipプロンプト
  # ===========================================================================
  # Rust製の高速でカスタマイズ可能なプロンプト
  # Git状態、言語バージョン、実行時間などを表示
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      add_newline = false; # プロンプト前の空行を無効化
    };
  };

  # ===========================================================================
  # Zoxide（スマートcd）
  # ===========================================================================
  # 移動履歴を学習し、部分一致でディレクトリにジャンプ
  # 例: z proj → ~/projects/myproject に移動
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # ===========================================================================
  # Direnv（ディレクトリごとの環境変数）
  # ===========================================================================
  # .envrcファイルでディレクトリ進入時に自動で環境をロード
  # nix-direnv: flake.nixを使った開発環境の自動切り替え
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # use flake で nix develop 環境を自動ロード
  };

  # ===========================================================================
  # fzf（ファジーファインダー）
  # ===========================================================================
  # ファイル選択、履歴検索、ディレクトリジャンプに使用
  programs.fzf = {
    enable = true;
    enableFishIntegration = true; # Ctrl+R（履歴）, Ctrl+T（ファイル）, Alt+C（ディレクトリ）
    defaultOptions = [
      "--height 40%"
      "--reverse"
      "--border"
    ];
  };

  # ===========================================================================
  # bat（cat代替）
  # ===========================================================================
  # シンタックスハイライト、行番号、Git統合を備えたcat
  programs.bat = {
    enable = true;
    config = {
      theme = "gruvbox-dark";
      style = "numbers,changes"; # 行番号とGit変更マーカーを表示
    };
  };

}
