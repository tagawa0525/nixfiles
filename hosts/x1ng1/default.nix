# =============================================================================
# x1ng1 (ThinkPad X1 Nano 1st Gen) 固有の設定
# =============================================================================
# このホストのみに適用される設定。
# 共通設定は modules/profiles/、ブート設定は modules/boot-lanzaboote.nix を参照。
# =============================================================================

{ ... }:
{
  imports = [
    ./hardware-configuration.nix # nixos-generate-config で生成されたハードウェア設定
    ../../modules/boot-lanzaboote.nix # Secure Boot共通設定
    # ../../modules/boot-initial.nix # Non Secure Boot共通設定 (新規ホスト初期セットアップ用テンプレ)
    ../../modules/profiles/laptop.nix # Laptop 共通（TLP、distributed-builds/client）
    ../../modules/profiles/workstation.nix # GUI 開発機共通（COSMIC、fcitx5、virt-manager 等）
    ../../modules/users/tagawa.nix # 住人: tagawa
  ];

  # ===========================================================================
  # ネットワーク
  # ===========================================================================
  networking.hostName = "x1ng1";

  # 内蔵LTEモデム (Intel XMM7360 / PCI 8086:7360):
  # nixpkgs の ModemManager 1.24.2 は XMM7360 RPC モード未対応のため、
  # かつて main HEAD (1.25.95-dev + MR !1421) を overlay で取り込む構成を
  # 試したが、ModemManager 上は attach APN セットまで到達したものの
  # modem 側で PLMN サーチが成立せず実通信に至らなかった。
  # nixpkgs を update するたびに 5 時間級の再ビルドを背負うのは割に合わないため overlay は一旦撤去。
  # ModemManager 自体は他の WWAN デバイス用に有効化したまま残す
  # (XMM7360 は認識されないが、enable しても害はない)。
  # 検討の経緯と再現手順は docs/x1ng1-xmm7360-lte.md を参照。
  # 1.26.0 stable / xmm7360-pci 併用を後日検討する。
  networking.modemmanager.enable = true;

  # ===========================================================================
  # 電源管理（ホスト固有: TLP 充電閾値）
  # ===========================================================================
  # 充電上限を 80% に制限してリチウムイオンの劣化を抑制。
  # 出張等で満充電したい時は `sudo tlp fullcharge BAT0` で一時解除（再起動で復帰）。
  services.tlp.settings = {
    START_CHARGE_THRESH_BAT0 = 75;
    STOP_CHARGE_THRESH_BAT0 = 80;
  };

  # ===========================================================================
  # システムバージョン
  # ===========================================================================
  # NixOSの互換性バージョン。初回インストール時のバージョンを維持。
  # アップグレード時も変更しないこと（データ移行の問題を避けるため）
  system.stateVersion = "26.05";
}
