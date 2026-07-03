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
  # フォント
  # ===========================================================================
  # 日本語表示に必要なフォントと開発用フォントをインストール
  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans # Google Noto日本語フォント
    noto-fonts-color-emoji # 絵文字フォント
    nerd-fonts.jetbrains-mono # 開発用フォント（アイコン付き）
    font-awesome # アイコンフォント（ステータスバー等で使用）
  ];
  # システム全体のデフォルトフォントを日本語対応に設定
  fonts.fontconfig = {
    defaultFonts = {
      sansSerif = [
        "Noto Sans CJK JP"
        "Noto Sans"
      ];
      monospace = [
        "Noto Sans Mono CJK JP"
        "Noto Sans Mono"
      ];
    };
  };

  # ===========================================================================
  # キーリマップ (keyd)
  # ===========================================================================
  # Wayland/X11/TTY全てで動作するキーリマッパー
  # CapsLockを「単独押し=Esc」「長押し/組み合わせ=Ctrl」に変更
  # Vim使用時に非常に便利
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ]; # 全キーボードに適用
      settings.main = {
        capslock = "overload(control, esc)";
      };
    };
  };

  # ===========================================================================
  # XDGユーザーディレクトリ
  # ===========================================================================
  # ホームディレクトリの標準フォルダ構成を定義
  environment.etc."xdg/user-dirs.defaults".text = ''
    DESKTOP=Desktop
    DOWNLOAD=Downloads
    TEMPLATES=Templates
    PUBLICSHARE=Public
    DOCUMENTS=Documents
    MUSIC=Music
    PICTURES=Pictures
    VIDEOS=Videos
  '';

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
    lib.mkForce [
      ""
      "${script}"
    ];

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

    # ターミナル
    alacritty # Rust製GPU加速ターミナル。設定はYAML

    # エディタ GUI
    neovide # Neovim用GUI。アニメーションやIME対応が優秀

    # Wayland ユーティリティ
    wl-clipboard # Wayland用クリップボード操作（wl-copy, wl-paste）
    waypipe # WaylandアプリをSSH経由で転送。リモートGUIアプリの実行に使用

    # システムモニタ
    cosmic-ext-applet-minimon # COSMICパネル用システムモニター

    # 開発用 GUI ツール
    podman-desktop # コンテナ管理GUI。Docker Desktopの代替
    meld # ファイル/ディレクトリの差分比較・マージ
    dbeaver-bin # 多数のDBに対応したGUIクライアント
  ];

  # ===========================================================================
  # GNOME Keyring
  # ===========================================================================
  # SSH鍵、GPG鍵、アプリのパスワードを安全に保管
  # ログイン時（コンソール / cosmic-greeter どちらでも）に自動でアンロックされる
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;
}
