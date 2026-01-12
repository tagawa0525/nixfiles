# =============================================================================
# tagawa用のHome Manager設定
# =============================================================================
# ユーザー固有の設定（ドットファイル、シェル設定、アプリ設定など）を定義
# システム設定（common.nix）とは別に、ユーザー空間の設定を管理
# =============================================================================
{
  pkgs,
  niriOutputConfig ? "",
  ...
}:

{
  imports = [
    ./niri.nix # Niriウィンドウマネージャの設定
    ./shell.nix # Fish, Starship, Zoxide, Direnv
    ./editors.nix # VSCode, Neovim, Zed, Alacritty
    ./desktop.nix # COSMIC, XDG, fcitx5, mimeApps
    ./development.nix # Git, activation scripts
  ];

  # niriOutputConfigをniri.nixに渡す（ホスト固有のディスプレイ設定用）
  _module.args.niriOutputConfig = niriOutputConfig;

  # Home Managerのバージョン（変更しない）
  home.stateVersion = "25.11";

  # ===========================================================================
  # ユーザーパッケージ
  # ===========================================================================
  home.packages = with pkgs; [
    fastfetch # システム情報表示（neofetchの高速版）
  ];
}
