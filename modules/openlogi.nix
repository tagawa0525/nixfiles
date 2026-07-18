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
{ pkgs, lib, ... }:

let
  # ローカルビルド（cargo build --release）の成果物パス。nixpkgs 化していない
  # 試用段階のため、リポジトリの場所をここに直書きする
  openlogiRepo = "/home/tagawa/github/OpenLogi";

  # GPUI (Zed の UI フレームワーク) は libwayland-client / libvulkan を
  # リンクせず実行時に dlopen する。NixOS では既定の検索パスにこれらが
  # 存在しないため、LD_LIBRARY_PATH で供給するラッパーを介して起動する。
  #
  # ここで注入する wayland / vulkan-loader はシステムクロージャに入り
  # GC root される。ただしバイナリ自身の実行時クロージャ（interpreter の
  # glibc や RUNPATH 先）は devenv 側の gc root（~/github/OpenLogi/.devenv）
  # 頼みで、このモジュールでは root しない（cargo 成果物は可変なため
  # nix 側から追跡できない）。
  #
  # 既知のトレードオフ（意図的に許容）:
  # - 注入 lib は nixfiles の lock、バイナリの glibc は devenv の lock 由来。
  #   flake update で glibc がずれると "version GLIBC_x.xx not found" で
  #   起動に失敗しうる。その場合は OpenLogi 側を再ビルドして揃える
  # - LD_LIBRARY_PATH は GUI の子プロセスにも継承される。注入するのが
  #   ほぼ全アプリがリンク済みの wayland / vulkan-loader のみのため実害は
  #   想定しない（GUI 側で unset しない限り継承自体は避けられない）
  openlogi-gui-wrapper = pkgs.writeShellScriptBin "openlogi-gui" ''
    bin=${openlogiRepo}/target/release/openlogi-gui
    if [ ! -x "$bin" ]; then
      msg="openlogi-gui が見つかりません: $bin （cargo build --release が必要）"
      echo "$msg" >&2
      # ランチャー起動では stderr が journal にしか残らないため通知も出す
      command -v notify-send > /dev/null && notify-send "OpenLogi" "$msg"
      exit 127
    fi
    export LD_LIBRARY_PATH=${
      lib.makeLibraryPath [
        pkgs.wayland
        pkgs.vulkan-loader
      ]
    }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    exec "$bin" "$@"
  '';

  # ランチャー（COSMIC 等）は XDG_DATA_DIRS 上の share/applications を読む。
  # upstream の install.sh は /usr/share/applications 前提で NixOS では無効
  # なため、システムパッケージとして .desktop を配置する
  openlogi-desktop = pkgs.makeDesktopItem {
    name = "openlogi";
    desktopName = "OpenLogi";
    comment = "Logitech HID++ device control — remap buttons, DPI, SmartShift";
    # ラッパーは systemPackages で PATH に載るため、store パスを埋め込まず
    # コマンド名で参照する（埋め込むとラッパー編集のたびに再ビルドが波及する）
    exec = "openlogi-gui";
    # アイコンも working tree の生ファイル参照。pure eval では flake 外の
    # 絶対パスを store へ取り込めないため、バイナリと同じトレードオフに含める
    # （リポジトリ移動時はアイコンだけ汎用プレースホルダに落ちる）
    icon = "${openlogiRepo}/design/icon/openlogi.png";
    categories = [
      "Settings"
      "HardwareSettings"
    ];
    keywords = [
      "logitech"
      "mouse"
      "hid"
      "remap"
      "dpi"
    ];
    startupNotify = true;
  };
in
{
  # uinput カーネルモジュールのロード（ボタンリマップ用の仮想入力デバイス作成に必要）
  hardware.uinput.enable = true;

  environment.systemPackages = [
    openlogi-gui-wrapper
    openlogi-desktop
  ];

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
