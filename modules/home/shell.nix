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
      cat = "bat"; # シンタックスハイライト付きcat
    };
    # NixOS再構築用コマンド（flake.lockの自動同期付き）
    functions = {
      # rebuild: リモートのflake.lockを取得してからrebuild
      rebuild = ''
        set -l nixdir ~/nix/nixfiles
        cd $nixdir
        echo "📥 Pulling flake.lock from remote..."
        git fetch origin main
        # ローカルに未コミットの変更がなければリモート版を取得
        if not git diff --quiet flake.lock 2>/dev/null
          echo "⚠️  flake.lock has local changes, skipping pull"
        else
          git checkout origin/main -- flake.lock 2>/dev/null; or echo "No remote changes to flake.lock"
        end
        echo "🔨 Rebuilding NixOS..."
        sudo nixos-rebuild switch --flake .
      '';
      # update: flake更新後に自動コミット＆プッシュ
      update = ''
        set -l nixdir ~/nix/nixfiles
        cd $nixdir
        echo "📥 Pulling flake.lock from remote..."
        git fetch origin main
        # ローカルに未コミットの変更がなければリモート版を取得
        if not git diff --quiet flake.lock 2>/dev/null
          echo "⚠️  flake.lock has local changes, skipping pull"
        else
          git checkout origin/main -- flake.lock 2>/dev/null; or echo "No remote changes to flake.lock"
        end
        echo "⬆️  Updating flake..."
        nix flake update
        echo "🔨 Rebuilding NixOS..."
        sudo nixos-rebuild switch --flake .
        echo "📤 Pushing flake.lock to remote..."
        git add flake.lock
        git commit -m "flake: update" 2>/dev/null; or echo "No changes to commit"
        git push
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

}
