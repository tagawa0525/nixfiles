# =============================================================================
# x1ng1 (ThinkPad X1 Nano 1st Gen) 固有の設定
# =============================================================================
# このホストのみに適用される設定。
# 共通設定は modules/common.nix を参照。
# ブート設定は modules/boot-initial.nix (Non Secure Boot) を使用しており、
# Secure Boot を有効化する場合は modules/boot-lanzaboote.nix に切り替える。
# =============================================================================

{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix # nixos-generate-config で生成されたハードウェア設定
    # ../../modules/boot-lanzaboote.nix # Secure Boot共通設定
    ../../modules/boot-initial.nix # Non Secure Boot共通設定
    ../../modules/nix-distributed-builds/client.nix # 重いビルドを r995 にオフロード
  ];

  # ===========================================================================
  # ネットワーク
  # ===========================================================================
  networking.hostName = "x1ng1";

  # 内蔵LTEモデム (Intel XMM7360 / PCI 8086:7360)
  # カーネル 7.0.x の iosm ドライバが /dev/wwan0at0,at1,xmmrpc0 を生成するが、
  # XMM7360 は Intel 独自の XMM RPC モードで初期化される。
  # nixpkgs の ModemManager 1.24.2 はこの RPC モードに未対応のため、
  # XMM7360 RPC サポートが入った dev tag 1.25.95-dev で上書きする。
  # 1.26.0 stable が nixpkgs に取り込まれたら overlay ごと削除する。
  # lib.mkAfter で末尾に積み、他 overlay による上書きを避ける。
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      modemmanager = prev.modemmanager.overrideAttrs (_oldAttrs: rec {
        version = "1.25.95-dev";
        src = prev.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "mobile-broadband";
          repo = "ModemManager";
          rev = version;
          hash = "sha256-xyb9LTkuJyTqt0yWDDJTYiICFVFJ5SqRlnOdrhrL2Ps=";
        };
      });
    })
  ];
  networking.modemmanager.enable = true;

  # ===========================================================================
  # 電源管理
  # ===========================================================================
  # TLP: ラップトップ向けの電源管理。バッテリー寿命を最適化
  # CPU周波数、ディスクスピンダウン、USB省電力などを自動調整
  services.tlp.enable = true;
  # COSMIC DEはデフォルトでpower-profiles-daemonを有効にするため、
  # TLPと競合しないよう明示的に無効化
  services.power-profiles-daemon.enable = false;

  # ===========================================================================
  # システムバージョン
  # ===========================================================================
  # NixOSの互換性バージョン。初回インストール時のバージョンを維持。
  # アップグレード時も変更しないこと（データ移行の問題を避けるため）
  system.stateVersion = "26.05";
}
