# =============================================================================
# r995 (デスクトップ) 固有の設定
# =============================================================================
# Ryzen 9950X + AMD Radeon Graphics のハイエンドデスクトップ設定。
# 共通設定は modules/common.nix を参照。
# =============================================================================
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix  # nixos-generate-config で生成されたハードウェア設定
  ];

  # ===========================================================================
  # ブート設定
  # ===========================================================================
  # Lanzabooteを使用したSecure Boot対応
  # UEFIのSecure Bootを有効にしたまま、自己署名したカーネルで起動
  boot.loader.systemd-boot.enable = lib.mkForce false;  # lanzabooteと競合するため無効化
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";  # sbctlで管理するSecure Boot鍵の保存場所
  };

  boot.resumeDevice = "/dev/disk/by-label/swap";

  # 最新のLinuxカーネルを使用（Ryzen 9000シリーズのサポート向上のため）
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ===========================================================================
  # AMD GPU設定
  # ===========================================================================
  # AMDGPUドライバーを使用（オープンソース）
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Vulkan / OpenGL サポート
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # 32ビットアプリ（Steam等）のサポート
  };

  # AMD GPU用の追加パッケージ
  hardware.graphics.extraPackages = with pkgs; [
    # amdvlk           # AMD公式Vulkanドライバー
    rocmPackages.clr # OpenCLサポート（GPGPU計算用）
  ];

  # ===========================================================================
  # ネットワーク
  # ===========================================================================
  networking.hostName = "r995";

  # ===========================================================================
  # システムバージョン
  # ===========================================================================
  # NixOSの互換性バージョン。初回インストール時のバージョンを維持。
  # アップグレード時も変更しないこと（データ移行の問題を避けるため）
  system.stateVersion = "25.11";
}
