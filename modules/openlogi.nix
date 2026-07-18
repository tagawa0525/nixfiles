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
        # Logitech HID++ レシーバー / 直結デバイス (hidraw)。
        # USB (Unifying/Bolt) は idVendor で sysfs 親をたどって照合し、
        # Bluetooth (uhid 仮想バス) は idVendor が無いためカーネル名
        # "bus:VID:PID.iface"（VID は大文字）で照合する
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", TAG+="uaccess"
        SUBSYSTEM=="hidraw", KERNELS=="*:046D:*", TAG+="uaccess"

        # evdev フック用: Logitech の入力イベントノードのみ開放する。
        # input グループ追加（upstream の非 systemd 向け手順）より範囲が狭く、
        # 他ベンダーのキーボード等は読めないままにできる
        SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="046d", TAG+="uaccess"
        SUBSYSTEM=="input", KERNEL=="event*", KERNELS=="*:046D:*", TAG+="uaccess"

        # uinput ノード。static_node によりデバイス挿抜を待たず起動時から
        # ノードが存在し、エージェントが即座に開ける
        KERNEL=="uinput", TAG+="uaccess", OPTIONS+="static_node=uinput"
      '';
    })
  ];
}
