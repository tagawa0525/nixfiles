# =============================================================================
# OpenLogi (Logitech Options+ 代替) のデバイスアクセス許可
# =============================================================================
# https://github.com/AprilNEA/OpenLogi
# ローカルビルドした openlogi / openlogi-agent / openlogi-gui が root なしで
# Logitech デバイスを扱うための udev ルール。upstream 同梱の
# packaging/linux/udev/70-openlogi.rules を基に、evdev フック用の入力イベント
# ノード開放（Logitech 限定）を追加している。
#
# uaccess タグは systemd-logind がアクティブシートのユーザーに ACL を付与する
# 仕組みで、ユーザー名やグループ追加を書かずに済む。ただしタグ付与は
# 73-seat-late.rules より前に行われる必要があるため、99-local.rules になる
# services.udev.extraRules ではなく、services.udev.packages で
# 70-openlogi.rules として配置する。
#
# セキュリティ上のトレードオフ（意図的に許容）:
# - uaccess の ACL はアクティブシートの「全」プロセスに付く。つまりデスクトップ
#   ユーザーとして動く任意のプロセスが (1) uinput で仮想入力デバイスを作り
#   キー入力を注入できる (2) Logitech の入力イベントノードを生で読める
#   （Logitech キーボードを接続した場合はキーロガー面になる。現用キーボードは
#   Topre のため対象外） (3) レシーバーへ生 HID++ を書ける（ペアリング操作等）。
#   root なしで動くデバイス管理ツール（Solaar 等も同様）に固有の面であり、
#   OpenLogi を使う前提で許容する。
# - ACL はアクティブなローカルセッションにのみ付与される。SSH セッションや
#   ヘッドレス起動ではエージェントは uinput / evdev を開けないが、
#   デスクトップ専用ツールなので意図通り。
# =============================================================================
{ pkgs, ... }:

{
  # uinput カーネルモジュールのロード（ボタンリマップ用の仮想入力デバイス作成に必要）
  hardware.uinput.enable = true;

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "openlogi-udev-rules";
      destination = "/etc/udev/rules.d/70-openlogi.rules";
      text = ''
        # Logitech (VID 046d) の hidraw / 入力イベントノードを開放する。
        # HID デバイスのカーネル名は USB・Bluetooth (uhid) とも
        # "bus:VID:PID.iface" 形式（VID は大文字 hex）なので、KERNELS で
        # sysfs の親をたどる 1 本で両トランスポートを照合できる
        # （upstream は ATTRS{idVendor} 併用の 2 本立てだが、USB も
        # KERNELS 側にマッチするため冗長で、ここでは簡約している）
        SUBSYSTEM=="hidraw", KERNELS=="*:046D:*", TAG+="uaccess"
        SUBSYSTEM=="input", KERNEL=="event*", KERNELS=="*:046D:*", TAG+="uaccess"

        # uinput ノード。static_node によりデバイス挿抜を待たず起動時から
        # ノードが存在し、エージェントが即座に開ける
        KERNEL=="uinput", TAG+="uaccess", OPTIONS+="static_node=uinput"
      '';
    })
  ];
}
