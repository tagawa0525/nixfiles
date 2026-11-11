# =============================================================================
# tagawa ユーザーの Home Manager 個人設定
# =============================================================================
# 全ホスト共通で適用される tagawa の個人設定。
# 共有部品は ../../parts/ から import。
# システムユーザー定義・authorized_keys・HM 紐付けは modules/users/tagawa.nix。
# =============================================================================
{
  pkgs,
  claude-harness,
  ...
}:

{
  imports = [
    ../../parts/shell.nix # Fish, Starship, Zoxide, Direnv, fzf, bat
    ../../parts/zellij.nix # Zellij設定と接続スクリプト
    ../../parts/editors.nix # VSCode, Neovim, Zed, Alacritty
    ../../parts/desktop.nix # COSMIC, XDG, fcitx5, mimeApps
    ../../parts/communication.nix # Discord, Zoom などお仕事用GUIアプリ
    ../../parts/git.nix # Git, delta, GitHub CLI
    ../../parts/claude-apps.nix # Claude Code CLI, Claude Desktop の本体
    claude-harness.homeManagerModules.default # ~/.claude の中身と settings.json、git のグローバルの hook（別のリポジトリ）
    ../../parts/development.nix # 開発ツール, activation scripts
    ../../parts/mise.nix # mise（ランタイムバージョンマネージャー）
    ../../parts/vscode-server.nix # VS Code Server自動パッチ（NixOS用）
    ../../parts/r995-link.nix # ~/r995/github（r995 の NFS を宣言したホストだけ）
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
