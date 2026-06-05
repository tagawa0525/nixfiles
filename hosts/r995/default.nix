# =============================================================================
# r995 (デスクトップ) 固有の設定
# =============================================================================
# Ryzen 9950X + AMD Radeon Graphics のハイエンドデスクトップ設定。
# 共通設定は modules/common.nix、ブート設定は modules/boot-lanzaboote.nix を参照。
#
# SSH の authorized_keys は modules/ssh-authorized-keys.nix が
# modules/home/users/<userName>/keys/*.pub を自動集約するため、
# 新ユーザーを追加する際もそのディレクトリに .pub を置くだけでよい。
# =============================================================================
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix # nixos-generate-config で生成されたハードウェア設定
    ../../modules/boot-lanzaboote.nix # Secure Boot共通設定
    # ../../modules/boot-initial.nix # Non Secure Boot共通設定 (新規ホスト初期セットアップ用テンプレ)
    ../../modules/profiles/desktop.nix # Desktop 共通（distributed-builds/builder）
    ../../modules/profiles/workstation.nix # GUI 開発機共通（COSMIC、fcitx5、virt-manager 等）
    ../../modules/users/tagawa.nix # 住人: tagawa
  ];

  # ===========================================================================
  # AMD GPU設定
  # ===========================================================================
  # AMDGPUドライバーを使用（オープンソース）
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Vulkan / OpenGL サポート
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32ビットアプリ（Steam等）のサポート
  };

  # AMD GPU用の追加パッケージ
  hardware.graphics.extraPackages = with pkgs; [
    # amdvlk           # AMD公式Vulkanドライバー
    rocmPackages.clr # OpenCLサポート（GPGPU計算用）
  ];

  # ===========================================================================
  # Bluetooth (MediaTek mt7925e コンボチップ)
  # ===========================================================================
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # MT7925のファームウェアはUSB autosuspendのremote wakeupを正しく処理できず、
  # BT USBインターフェースが応答しなくなる既知の不具合がある。
  # デスクトップPCではautosuspendの省電力効果は不要なので無効化する。
  # https://bugzilla.redhat.com/show_bug.cgi?id=2372880
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  # ===========================================================================
  # ネットワーク
  # ===========================================================================
  networking.hostName = "r995";

  # ===========================================================================
  # Atuin サーバー（シェル履歴同期）
  # ===========================================================================
  # 常時通電のデスクトップ機を全ホスト共通の同期サーバーとする。
  # クライアント側（programs.atuin）は modules/home/parts/shell.nix を参照。
  # 履歴は E2E 暗号化された上で送られるため、サーバーは平文を復号できない。
  services.atuin = {
    enable = true;
    # 0.0.0.0 でlistenし、到達制御はファイアウォール（tailscale0のみ）で行う。
    # Tailscale 名 "r995" で他ホストから http://r995:8888 に接続する。
    host = "0.0.0.0";
    port = 8888;
    # 初回ユーザー登録に必要。全ホストの登録・login が済んだら false に戻して
    # 再 rebuild すると、以降の新規アカウント作成を拒否できる（推奨）。
    openRegistration = true;
    # database.createLocally = true（デフォルト）により PostgreSQL を
    # ローカルに自動作成する。
  };

  # Atuin サーバーへの接続は Tailscale 経由のみ許可する。
  # openFirewall = true は全インターフェースに穴を開けるため使わず、
  # tailscale0 インターフェース限定でポートを開放する。
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8888 ];

  # ===========================================================================
  # システムバージョン
  # ===========================================================================
  # NixOSの互換性バージョン。初回インストール時のバージョンを維持。
  # アップグレード時も変更しないこと（データ移行の問題を避けるため）
  system.stateVersion = "26.05";
}
