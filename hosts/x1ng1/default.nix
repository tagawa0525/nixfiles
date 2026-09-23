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

  # networking.hostName はディレクトリ名から flake.nix の mkHost が自動設定する

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

  # iosm (XMM7360 のカーネルドライバ) は読み込ませない。
  # 2026-09-07、iosm が IPC ハンドシェイクに失敗（`A-RUN: ipc_status(0) ne.
  # IPC_MEM_DEVICE_IPC_INIT`）した状態でサスペンドしたところ、s2idle から
  # 一切復帰しなくなり強制電源断以外に手がなくなった。当時は journal 13 boot
  # 分で iosm の初期化成否と復帰成否が一致していたため、これを引き金と判断した。
  #
  # ただし blacklist 後も復帰ハングは再発しており（16 回中 2 回）、iosm が
  # 原因だったという判断は崩れている。調査記録は
  # docs/x1ng1-power-management.md を参照。
  #
  # それでも blacklist は残す。上記のとおり LTE は現状まったく使えず、
  # ドライバを読み込む利益がない。また下の pm_trace で犯人を追う間は、
  # 条件を動かさない方が結果を解釈しやすい。LTE を再度試すとき
  # （ModemManager 1.26.0 stable 等）はこの行を消す。その場合は起動ごとに
  # `journalctl -b | grep iosm` で初期化の成否を確認すること。
  boot.blacklistedKernelModules = [ "iosm" ];

  # ===========================================================================
  # s2idle 復帰ハングの犯人特定（調査中）
  # ===========================================================================
  # iosm を blacklist した後も s2idle からの復帰ハングが 16 回中 2 回で再発して
  # おり、原因は特定できていない（docs/x1ng1-power-management.md）。ハング時は
  # journald が既に凍結しているため、journal は `PM: suspend entry` で途切れて
  # 手がかりが残らない。
  #
  # pm_trace: suspend/resume で処理中のデバイスのハッシュを RTC に書き込む。
  # RTC は電池でバックアップされているため強制電源断でも消えず、次回起動時に
  # カーネルが `hash matches` として該当デバイスを出力する。代償は 2 つある。
  #   - RTC の時刻が壊れる。起動後に timesyncd が直す
  #   - デバイスの suspend/resume が同期実行になる（カーネルの is_async() が
  #     pm_trace_is_enabled() を見るため）。タイミングが変わるので、ハングが
  #     起きにくくなる可能性がある
  #
  # pm_print_times / pm_debug_messages: 復帰に成功した場合だけ journal に残る。
  # 2026-09-23 10:05:42 のように遅れて戻ったレジュームで、どのデバイスに何 ms
  # かかったかを記録する。
  #
  # 犯人が特定できたら 3 行とも外す。
  systemd.tmpfiles.rules = [
    "w /sys/power/pm_trace - - - - 1"
    "w /sys/power/pm_print_times - - - - 1"
    "w /sys/power/pm_debug_messages - - - - 1"
  ];

  # ===========================================================================
  # 電源管理（ホスト固有: TLP 充電閾値）
  # ===========================================================================
  # 充電上限を 80% に制限してリチウムイオンの劣化を抑制。
  # 出張等で満充電したい時は `sudo tlp fullcharge BAT0` で一時解除（再起動で復帰）。
  # 閾値は EC の揮発性設定で電源オフ中は保持されない。AC を接続したまま
  # シャットダウンすると 100% まで充電され、起動後も放電するまで戻らない。
  # 蓋を閉じた際の消費（約 15%/日）や hibernate を断念した経緯とあわせて
  # docs/x1ng1-power-management.md を参照。
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
