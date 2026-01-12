# =============================================================================
# シェル関連の設定
# =============================================================================
# Fish, Tmux, Starship, Zoxide, Direnv などシェル環境の設定
# デフォルトシェルはbash、tmux内ではfishを使用
# =============================================================================
{ pkgs, ... }:

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
    '';
    # よく使うコマンドのエイリアス
    shellAliases = {
      ls = "eza"; # モダンなls
      ll = "eza -la"; # 詳細表示
      la = "eza -a"; # 隠しファイル含む
      lt = "eza --tree"; # ツリー表示
      cat = "bat"; # シンタックスハイライト付きcat
      # NixOS再構築用エイリアス（ホスト名を動的に取得）
      rebuild = "sudo nixos-rebuild switch --flake ~/NixOS#$(hostname)";
      update = "cd ~/NixOS && nix flake update && sudo nixos-rebuild switch --flake .#$(hostname)";
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
  # Tmux設定
  # ===========================================================================
  # ターミナル多重化。tmux内ではfishを使用
  programs.tmux = {
    enable = true;
    # tmux内ではfishを使用（デフォルトシェルはbashなのでVSCode-Serverも問題なし）
    shell = "${pkgs.fish}/bin/fish";
    # エスケープキーをCtrl+\に変更（Ctrl+Bから）
    prefix = "C-\\\\";
    # その他の設定
    escapeTime = 0; # Escキーの遅延をなくす
    historyLimit = 50000;
    mouse = true; # Alacrittyはマウス対応なので有効化
    terminal = "tmux-256color";
    extraConfig = ''
      # Ctrl+\ 2回押しで前のウィンドウに戻る
      bind C-\\ last-window

      # ビジュアルベル無効化
      set -g visual-bell off

      # ウィンドウ番号の自動リナンバリング無効化
      set -g renumber-windows off

      # ステータスライン設定
      set -g status-left "#{session_name} | "
      set -g status-right "%Y/%m/%d %H:%M"
      set -g window-status-current-style bg=white

      # クリップボード統合（Alacrittyで使用）
      set -g set-clipboard on
    '';
  };
}
