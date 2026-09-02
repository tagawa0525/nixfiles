# =============================================================================
# Workstation プロファイル（GUI 開発機向け共通設定）
# =============================================================================
# COSMIC DE、日本語入力、ブラウザ、仮想化マネージャ、GUI 開発ツール群など
# 「人が GUI で日常的に使う」ホストに乗せる設定をまとめる。
# Laptop でも Desktop でも乗る（profile = ホストの「種類」、本ファイル = 用途）。
# サーバー/最小ホストには適用しない。
# =============================================================================
{ pkgs, ... }:

{
  imports = [
    # Logitech マウス管理 (OpenLogi) のデバイスアクセス許可。
    # マウスは KVM で全ホストを行き来するため、GUI ホスト共通で適用する
    ../openlogi.nix

    # Delta（Zed 開発元の AI エディタ）を動かすための nix-ld / XKB の下駄。
    # 本体は ~/.local に手動導入する。使わなくなったらこの行ごと消す
    ../delta.nix
  ];

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
  # virt-secret-init-encryption の /usr/bin/sh 問題は nixpkgs の libvirt 12.6.0 が
  # runtimeShell + coreutils/systemd 入りラッパーへの置換で修正済みのため上書き不要

  # ===========================================================================
  # ブラウザ
  # ===========================================================================
  programs.firefox.enable = true;

  # ===========================================================================
  # Webカメラ / 配信 (OBS Studio)
  # ===========================================================================
  # Insta360 Link2 Pro は UVC 準拠のためカーネル標準の uvcvideo で認識される。
  # ジンバル制御・AIトラッキングはカメラ本体で完結するため専用ソフトは不要
  # （Insta360 Link Controller は Linux 非対応）。
  # パン・チルト・ズームは UVC 標準コマンドのため v4l2-ctl で手動制御できる。
  programs.obs-studio = {
    enable = true;
    # OBS の合成映像を仮想カメラ (/dev/videoN) としてブラウザ会議等に流す。
    # v4l2loopback カーネルモジュールの組み込みと設定も行われる
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      # Wayland 環境でのアプリ別音声キャプチャ。前提の PipeWire / rtkit は
      # nixpkgs の graphical-desktop.nix（COSMIC 有効時に自動 import）が
      # 有効化するため、ここでの明示的な設定は不要
      obs-pipewire-audio-capture
    ];
  };

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

    # カメラユーティリティ
    v4l-utils # v4l2-ctl による UVC カメラの設定・PTZ 制御
  ];

  # ===========================================================================
  # GNOME Keyring
  # ===========================================================================
  # SSH鍵、GPG鍵、アプリのパスワードを安全に保管
  # ログイン時（コンソール / cosmic-greeter どちらでも）に自動でアンロックされる
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;

  # ===========================================================================
  # GnuPG の pinentry
  # ===========================================================================
  # base プロファイルは pinentry-curses（TTY用）。GUIセッションでは端末を
  # 持たないアプリからも gpg が呼ばれるため、GTK版に差し替える
  programs.gnupg.agent.pinentryPackage = pkgs.pinentry-gnome3;
}
