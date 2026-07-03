# =============================================================================
# シェル関連の設定
# =============================================================================
# Fish, Starship, Zoxide, Direnv などシェル環境の設定
# デフォルトシェルはbash（tmux設定は tmux.nix を参照）
# =============================================================================

{ lib, ... }:

{
  # ===========================================================================
  # PATHの設定
  # ===========================================================================
  # ~/.local/bin をPATHに追加（カスタムスクリプト用）
  home.sessionPath = [ "$HOME/.local/bin" ];

  # ===========================================================================
  # 共通スクリプトのインストール
  # ===========================================================================
  # NixOS再構築用スクリプトを~/.local/bin/にインストール
  home.file.".local/bin/nix-rebuild" = {
    source = ../scripts/nix-rebuild.sh;
    executable = true;
  };
  # ===========================================================================
  # Fishシェル
  # ===========================================================================
  # モダンなシェル。強力な補完、シンタックスハイライト、履歴検索
  programs.fish = {
    enable = true;
    # 起動時のグリーティングメッセージを無効化
    interactiveShellInit = ''
      set -g fish_greeting
      # ~/.local/bin をPATHに追加（カスタムスクリプト用）
      fish_add_path --path ~/.local/bin
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
    # NixOS再構築用コマンド（共通スクリプトのラッパー）
    functions = {
      rebuild = "nix-rebuild rebuild";
      update = "nix-rebuild update";
    };
  };

  # ===========================================================================
  # Bashシェル
  # ===========================================================================
  # デフォルトシェル。fish関数と同じ機能をbashでも提供
  programs.bash = {
    enable = true;
    enableCompletion = true;
    # よく使うコマンドのエイリアス（fishと同じ）
    shellAliases = {
      ls = "eza";
      ll = "eza -la";
      la = "eza -a";
      lt = "eza --tree";
      cat = "bat";
    };
    # NixOS再構築用関数（共通スクリプトのラッパー）
    bashrcExtra = ''
      rebuild() { nix-rebuild rebuild; }
      update() { nix-rebuild update; }

      # mise有効化（Bashシェルで自動補完とコマンドが使えるようになる）
      if command -v mise &> /dev/null; then
        eval "$(mise activate bash)"
      fi
    '';
  };

  # ===========================================================================
  # Starshipプロンプト
  # ===========================================================================
  # Rust製の高速でカスタマイズ可能なプロンプト
  # Git状態、言語バージョン、実行時間などを表示
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
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
    enableBashIntegration = true;
  };

  # ===========================================================================
  # Direnv（ディレクトリごとの環境変数）
  # ===========================================================================
  # .envrcファイルでディレクトリ進入時に自動で環境をロード
  # nix-direnv: flake.nixを使った開発環境の自動切り替え
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true; # use flake で nix develop 環境を自動ロード
  };

  # ===========================================================================
  # fzf（ファジーファインダー）
  # ===========================================================================
  # ファイル選択、履歴検索、ディレクトリジャンプに使用
  programs.fzf = {
    enable = true;
    enableFishIntegration = true; # Ctrl+T（ファイル）, Alt+C（ディレクトリ）
    enableBashIntegration = true;
    # Ctrl+R は atuin が所有するため fzf 側のバインドを無効化
    # （Ctrl+T / Alt+C はそのまま有効）
    historyWidget.command = "";
    defaultOptions = [
      "--height 40%"
      "--reverse"
      "--border"
    ];
  };

  # ===========================================================================
  # Atuin（シェル履歴の同期・全文検索）
  # ===========================================================================
  # 履歴をSQLiteで管理し、Ctrl+Rで全文検索・実行コンテキスト付きで呼び出す。
  # 同期サーバーは r995 にセルフホスト（hosts/r995/default.nix を参照）。
  # 履歴はE2E暗号化されてから送られるため、サーバーは平文を復号できない。
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    # Ctrl+Rのみ atuin に置き換え、上矢印は通常のシェル履歴のまま残す。
    # （上矢印でも全文検索したい場合はこのフラグを外す）
    flags = [ "--disable-up-arrow" ];
    settings = {
      auto_sync = true; # バックグラウンドで自動同期
      sync_frequency = "5m"; # 同期間隔
      sync_address = "http://r995:8888"; # セルフホストサーバー（Tailscale名で解決）
      search_mode = "fuzzy"; # ファジー検索（fzf流のあいまい一致）
      style = "compact"; # コンパクト表示
    };
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
