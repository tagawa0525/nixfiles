# =============================================================================
# tagawa ユーザー設定（t14g4ラップトップ用）
# =============================================================================
# tagawa ユーザー専用の個人設定。
# 共通モジュールは ../common/ から import。
# =============================================================================
{ pkgs
, ...
}:

{
  imports = [
    ../../parts/shell.nix # Fish, Starship, Zoxide, Direnv, fzf, bat
    ../../parts/tmux.nix # Tmux設定と接続スクリプト
    ../../parts/editors.nix # VSCode, Neovim, Zed, Alacritty
    ../../parts/desktop.nix # COSMIC, XDG, fcitx5, mimeApps
    ../../parts/communication.nix # Discord, Zoom などお仕事用GUIアプリ
    ../../parts/git.nix # Git, Git Hooks, delta, GitHub CLI
    ../../parts/claude-code.nix # Claude Code CLI, hooks/skills同期, settings管理
    ../../parts/development.nix # 開発ツール, activation scripts
    ../../parts/mise.nix # mise（ランタイムバージョンマネージャー）
    ../../parts/vscode-server.nix # VS Code Server自動パッチ（NixOS用）
  ];

  # Home Managerのバージョン（変更しない）
  home.stateVersion = "26.05";

  # ===========================================================================
  # ユーザーパッケージ
  # ===========================================================================
  home.packages = with pkgs; [
    fastfetch # システム情報表示（neofetchの高速版）
    playwright-driver # Playwright（ブラウザ自動化ツール）
    playwright-test # Playwrightのテストランナー
  ];
}
