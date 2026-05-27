# =============================================================================
# Workstation プロファイル（GUI 開発機向け共通設定）
# =============================================================================
# COSMIC DE、日本語入力、ブラウザ、仮想化マネージャ、GUI 開発ツール群など
# 「人が GUI で日常的に使う」ホストに乗せる設定をまとめる。
# Laptop でも Desktop でも乗る（profile = ホストの「種類」、本ファイル = 用途）。
# サーバー/最小ホストには適用しない。
# =============================================================================
{ pkgs, lib, ... }:

{
  # ===========================================================================
  # 日本語入力 (fcitx5 + Mozc)
  # ===========================================================================
  # fcitx5: 入力メソッドフレームワーク
  # Mozc: Google日本語入力のオープンソース版
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc # 日本語変換エンジン
      fcitx5-gtk # GTKアプリとの統合
    ];
  };

  # ===========================================================================
  # 環境変数
  # ===========================================================================
  environment.sessionVariables = {
    # Electron/ChromiumアプリをWaylandネイティブで動作させる
    NIXOS_OZONE_WL = "1";
  };

  # ===========================================================================
  # デスクトップ環境 (COSMIC DE)
  # ===========================================================================
  # System76が開発中のRust製デスクトップ環境
  # Waylandネイティブでタイル型ウィンドウ管理をサポート
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  # ===========================================================================
  # 仮想化 (libvirt/KVM)
  # ===========================================================================
  # ハードウェア仮想化によるVM実行環境
  # Windows VM、開発環境の分離などに使用
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true; # VM管理用GUI
  # ユーザーの libvirtd グループ加入は user モジュール側で
  # config.virtualisation.libvirtd.enable をトリガーに条件付き追加する
  # （workstation profile を username 非依存に保つため）
  # NixOSではFHS準拠の/usr/binが存在しないため、このサービスを明示的に上書きする
  # ExecStartはリスト型なので空文字で既存エントリをクリアしてから置換する
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart =
    let
      script = pkgs.writeShellScript "virt-secret-init-encryption" ''
        umask 0077
        dd if=/dev/random status=none bs=32 count=1 \
          | ${pkgs.systemd}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key
      '';
    in
    lib.mkForce [ "" "${script}" ];

  # ===========================================================================
  # ブラウザ
  # ===========================================================================
  programs.firefox.enable = true;

  # ===========================================================================
  # GUI パッケージ
  # ===========================================================================
  environment.systemPackages = with pkgs; [
    # ブラウザ
    google-chrome # Chromiumベース。開発者ツールが充実

    # エディタ GUI
    neovide # Neovim用GUI。アニメーションやIME対応が優秀

    # システムモニタ
    cosmic-ext-applet-minimon # COSMICパネル用システムモニター

    # 開発用 GUI ツール
    podman-desktop # コンテナ管理GUI。Docker Desktopの代替
    meld # ファイル/ディレクトリの差分比較・マージ
    dbeaver-bin # 多数のDBに対応したGUIクライアント
  ];

  # ===========================================================================
  # COSMIC greeter の GNOME Keyring 連携
  # ===========================================================================
  # gnome-keyring 本体と login pam は base.nix で有効化済み
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;
}
