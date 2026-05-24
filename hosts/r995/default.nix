# =============================================================================
# r995 (デスクトップ) 固有の設定
# =============================================================================
# Ryzen 9950X + AMD Radeon Graphics のハイエンドデスクトップ設定。
# 共通設定は modules/common.nix、ブート設定は modules/boot-lanzaboote.nix を参照。
#
# SSH設定：
#   複数ユーザーを想定し、各ユーザーの authorized_keys を システム設定で管理。
#   ユーザー追加時に対応する authorized_keys.keyFiles を定義する。
# =============================================================================
{ pkgs, self, ... }:

{
  imports = [
    ./hardware-configuration.nix # nixos-generate-config で生成されたハードウェア設定
    ../../modules/boot-lanzaboote.nix # Secure Boot共通設定
    ../../modules/nix-distributed-builds/builder.nix # 他ホストからのリモートビルド受付
  ];

  # ===========================================================================
  # ユーザー SSH設定（複数ユーザー想定）
  # ===========================================================================
  # tagawa: 複数ホスト間の相互接続用
  # ユーザーの個人設定から公開鍵を参照
  users.users.tagawa.openssh.authorizedKeys.keyFiles = [
    "${self}/modules/home/users/tagawa/keys/t14g4.pub"
    "${self}/modules/home/users/tagawa/keys/r995.pub"
  ];

  # 将来的なユーザー追加時のテンプレート：
  # users.users.<newuser>.openssh.authorizedKeys.keyFiles = [
  #   "${self}/modules/home/users/<newuser>/keys/<newuser>@r995.pub"
  # ];

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
  # システムバージョン
  # ===========================================================================
  # NixOSの互換性バージョン。初回インストール時のバージョンを維持。
  # アップグレード時も変更しないこと（データ移行の問題を避けるため）
  system.stateVersion = "26.05";
}
