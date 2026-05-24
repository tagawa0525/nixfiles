# =============================================================================
# x1ng1 (ThinkPad X1 Nano 1st Gen) 固有の設定
# =============================================================================
# このホストのみに適用される設定。
# 共通設定は modules/common.nix を参照。
# ブート設定は modules/boot-initial.nix (Non Secure Boot) を使用しており、
# Secure Boot を有効化する場合は modules/boot-lanzaboote.nix に切り替える。
# =============================================================================

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
  # 現状: 動作させていない。理由は以下。
  #   - カーネル 7.0.x の iosm ドライバはハードウェアを認識し
  #     /dev/wwan0at0,at1,xmmrpc0 を生成するが、XMM7360 は Intel 独自の
  #     XMM RPC モードで初期化される (XMM7560 用の MBIM モードではない)。
  #   - ModemManager 1.24.2 はこの RPC モードに未対応で、probe 段階で
  #     "Intel XMM7360 in RPC mode not supported" として弾かれる。
  #   - AT ポート (wwan0at0/at1) も RPC ハンドシェイク前は応答せず、
  #     ATコマンドによる MBIM モード切替も不可。
  # 再開条件:
  #   1) mainline iosm + ModemManager に XMM7360 RPC サポートが入る、または
  #   2) コミュニティドライバ xmm7360-pci のカーネル 7.x 対応フォークを
  #      flake で追加し iosm を blacklist して使う。
  # 当面は Wi-Fi / テザリングで運用。LTE を有効化する際は以下を追加:
  #   networking.modemmanager.enable = true;

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
