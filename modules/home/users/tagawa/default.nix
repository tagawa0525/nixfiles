# =============================================================================
# tagawa ユーザー設定（t14g4ラップトップ用）
# =============================================================================
# tagawa ユーザー専用の個人設定。
# 共通モジュールは ../common/ から import。
# =============================================================================
{ pkgs
, niriOutputConfig ? ""
, ...
}:

{
  imports = [
    ../../common/niri.nix # Niriウィンドウマネージャの設定
    ../../common/shell.nix # Fish, Starship, Zoxide, Direnv, fzf, bat
    ../../common/tmux.nix # Tmux設定と接続スクリプト
    ../../common/editors.nix # VSCode, Neovim, Zed, Alacritty
    ../../common/desktop.nix # COSMIC, XDG, fcitx5, mimeApps
    ../../common/communication.nix # Discord, Zoom などお仕事用GUIアプリ
    ../../common/git.nix # Git, Git Hooks, delta, GitHub CLI
    ../../common/claude-code.nix # Claude Code CLI, hooks/skills同期, settings管理
    ../../common/development.nix # 開発ツール, activation scripts
    ../../common/mise.nix # mise（ランタイムバージョンマネージャー）
    ../../common/vscode-server.nix # VS Code Server自動パッチ（NixOS用）
  ];

  # niriOutputConfigをniri.nixに渡す（ホスト固有のディスプレイ設定用）
  _module.args.niriOutputConfig = niriOutputConfig;

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
