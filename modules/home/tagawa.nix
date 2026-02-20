# =============================================================================
# tagawa用のHome Manager設定
# =============================================================================
# ユーザー固有の設定（ドットファイル、シェル設定、アプリ設定など）を定義
# システム設定（common.nix）とは別に、ユーザー空間の設定を管理
# =============================================================================
{ pkgs
, niriOutputConfig ? ""
, ...
}:

{
  imports = [
    ./niri.nix # Niriウィンドウマネージャの設定
    ./shell.nix # Fish, Starship, Zoxide, Direnv, fzf, bat
    ./tmux.nix # Tmux設定と接続スクリプト
    ./editors.nix # VSCode, Neovim, Zed, Alacritty
    ./desktop.nix # COSMIC, XDG, fcitx5, mimeApps
    ./git.nix # Git, Git Hooks, delta, GitHub CLI
    ./claude-code.nix # Claude Code CLI, hooks/skills同期, settings管理
    ./development.nix # 開発ツール, activation scripts
    ./mise.nix # mise（ランタイムバージョンマネージャー）
    ./vscode-server.nix # VS Code Server自動パッチ（NixOS用）
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
