# =============================================================================
# OpenLogi (Logitech Options+ 代替) の統合
# =============================================================================
# https://github.com/tagawa0525/OpenLogi （upstream: AprilNEA/OpenLogi の fork）
#
# パッケージ本体は flake input `openlogi`（fork の flake）が出す Linux 向け
# パッケージを flake.nix の overlay 経由で受け取る。以前はローカルの cargo
# 成果物（~/github/OpenLogi/target）を直接参照していたが、そのパスを持たない
# x1ng1 / t14g4 では動かせず、nix flake update でも更新されなかったため
# input 化した。
#
# このモジュールが持つのは「システム側に要る設定」だけ:
#   - デバイスアクセス許可 (udev + uinput)
#   - エージェントの常駐 (systemd user service)
#   - パッケージの導入
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

  # openlogi (CLI) / openlogi-agent / openlogi-gui と .desktop・アイコンを含む。
  # パッケージは udev ルールと systemd user unit も同梱するが、どちらも
  # services.udev.packages / systemd.packages に載せない限り効かないので、
  # 下の宣言（簡約した udev ルールと unit）だけが実際に使われる
  environment.systemPackages = [ pkgs.openlogi ];

  # エージェントの常駐。パッケージ同梱の unit は使わず、順序と再起動条件を
  # 明示した同等の内容をここに持つ（ExecStart は overlay 経由の store パス）。
  #
  # GUI の「ログイン時に起動」設定は agent 自身に
  # $XDG_CONFIG_HOME/systemd/user/openlogi-agent.service を書かせる。そちらは
  # /etc/systemd/user のこの unit より優先されるので、両方あると nix 側の
  # 定義が黙って無視される。移行時は手書きの unit を削除すること。
  systemd.user.services.openlogi-agent = {
    description = "OpenLogi background agent (Logitech HID++ device control)";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.openlogi}/bin/openlogi-agent";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

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
