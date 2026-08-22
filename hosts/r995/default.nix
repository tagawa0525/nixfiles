# =============================================================================
# r995 (デスクトップ) 固有の設定
# =============================================================================
# Ryzen 9950X + AMD Radeon Graphics のハイエンドデスクトップ設定。
# 共通設定は modules/profiles/、ブート設定は modules/boot-lanzaboote.nix を参照。
# =============================================================================
{ lib, pkgs, ... }:

let
  # KVM HIDハブ復旧スクリプト。手動実行（SSH経由）と自動復旧サービスの両方で使う
  kvm-hid-reset = pkgs.writeShellApplication {
    name = "kvm-hid-reset";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./kvm-hid-reset.sh;
  };

  # devcoredump 退避スクリプト。udev 経由の devcoredump-save@ サービスから使う
  devcoredump-save = pkgs.writeShellApplication {
    name = "devcoredump-save";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      dev="$1" # 例: devcd1
      src="/sys/class/devcoredump/$dev"
      dest=/var/lib/devcoredump
      mkdir -p "$dest"
      # failing_device は障害元デバイス（例: PCI の 0000:72:00.0）への symlink
      failing="$(basename "$(readlink -f "$src/failing_device")")"
      out="$dest/$(date +%Y%m%d-%H%M%S)-$failing.dump"
      cp "$src/data" "$out"
      # data への書き込みは dump の解放。保持したままだと同一デバイスの
      # 次の障害が capture されないため、退避後は即座に解放する
      echo 1 > "$src/data"
      echo "saved: $out"
    '';
  };
in
{
  imports = [
    ./hardware-configuration.nix # nixos-generate-config で生成されたハードウェア設定
    ../../modules/boot-lanzaboote.nix # Secure Boot共通設定
    # ../../modules/boot-initial.nix # Non Secure Boot共通設定 (新規ホスト初期セットアップ用テンプレ)
    ../../modules/profiles/desktop.nix # Desktop 共通（distributed-builds/builder）
    ../../modules/profiles/workstation.nix # GUI 開発機共通（COSMIC、fcitx5、virt-manager 等）
    ../../modules/nix-auto-update.nix # 毎朝の flake update + 全ホスト検証 + push
    ../../modules/users/tagawa.nix # 住人: tagawa
  ];

  # ===========================================================================
  # AMD GPU設定
  # ===========================================================================
  # ドライバはカーネルの amdgpu + Mesa が自動で使われるため明示指定は不要。
  # enable32Bit は Steam/Wine 等の32bitアプリを使う場合に programs.steam.enable
  # 等が自動で有効化する。OpenCL (rocmPackages.clr) は開発用途ならプロジェクトの
  # devShell で OCL_ICD_VENDORS を指定すれば足りるためシステム側には置かない。
  hardware.graphics.enable = true; # Vulkan / OpenGL サポート

  # ===========================================================================
  # Bluetooth (MediaTek mt7925e コンボチップ)
  # ===========================================================================
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # MT7925のファームウェアはUSB autosuspendのremote wakeupを正しく処理できず、
  # BT USBインターフェースが応答しなくなる既知の不具合がある。
  # https://bugzilla.redhat.com/show_bug.cgi?id=2372880
  # 対策は当該デバイス (13d3:3602) 限定の udev ルール（下記
  # services.udev.extraRules）。以前は usbcore.autosuspend=-1 で全USBの
  # autosuspend を止めていたが、KVM・ハブ等の無関係なデバイスまで巻き込む
  # ため範囲を絞った。BTハングが再発する場合は btusb.enable_autosuspend=0
  # （btusb 全体）への拡大を検討する。

  # networking.hostName はディレクトリ名から flake.nix の mkHost が自動設定する

  # ===========================================================================
  # Atuin サーバー（シェル履歴同期）
  # ===========================================================================
  # 常時通電のデスクトップ機を全ホスト共通の同期サーバーとする。
  # クライアント側（programs.atuin）は modules/home/parts/shell.nix を参照。
  # 履歴は E2E 暗号化された上で送られるため、サーバーは平文を復号できない。
  services.atuin = {
    enable = true;
    # 0.0.0.0 でlistenし、到達制御はファイアウォール（tailscale0のみ）で行う。
    # Tailscale 名 "r995" で他ホストから http://r995:8888 に接続する。
    host = "0.0.0.0";
    port = 8888;
    # 全ホストの登録・login が完了済みのため新規アカウント作成を拒否する。
    # 新ホスト追加時も既存アカウントへの login は可能（true に戻す必要はない）。
    openRegistration = false;
    # database.createLocally = true（デフォルト）により PostgreSQL を
    # ローカルに自動作成する。
    # atuin は TCP ではなく UNIX ソケット経由で接続するため、PostgreSQL の
    # ポートを既定の 5432 から退避させても、URI に新ポートを指定すれば動く。
    # こうすることで 5432 を別用途の PostgreSQL に明け渡せる。
    database.uri = "postgresql:///atuin?host=/run/postgresql&port=15432";
  };

  # atuin 用に作られる PostgreSQL を既定の 5432 から退避させ、衝突を避ける。
  services.postgresql.settings.port = 15432;

  # Atuin サーバーへの接続は Tailscale 経由のみ許可する。
  # openFirewall = true は全インターフェースに穴を開けるため使わず、
  # tailscale0 インターフェース限定でポートを開放する。
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8888
    41717 # kikitori エンジン（x1ng1 / t14g4 が tailnet 経由で使う。LAN 直は不可）
  ];

  # ===========================================================================
  # KVM HIDハブ復旧（手動コマンド + 自動復旧）
  # ===========================================================================
  # EIZO EV3895 内蔵KVMのHID用ハブは切替時にハングすることがあり、
  # キーボード・マウスが認識されなくなる。SSHから `kvm-hid-reset` を
  # 実行すれば再起動なしで復旧を試みられる。詳細は kvm-hid-reset.sh 参照。
  environment.systemPackages = [ kvm-hid-reset ];

  # KVM切替でHID用ハブ (2109:2817, 2ポート) が現れたら kvm-hid-watch を起動し、
  # 列挙の完了を待ってからHID欠落時のみ復旧を実行する。キーボードが死んだ
  # 状態では手動操作ができないため、ホスト側で自動復旧させる。
  # 同じ 2109:2817 の上流側ハブ (4ポート) は maxchild で除外する。
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2109", ATTR{idProduct}=="2817", ATTR{maxchild}=="2", TAG+="systemd", ENV{SYSTEMD_WANTS}+="kvm-hid-watch.service"
    # MT7925 BT: btusb が probe 時に有効化する autosuspend を打ち消す（Bluetoothセクション参照）
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="13d3", ATTR{idProduct}=="3602", ATTR{power/control}="on"
    # devcoredump が生成されたら退避サービスを起動する（下記 devcoredump-save@ 参照）
    ACTION=="add", SUBSYSTEM=="devcoredump", TAG+="systemd", ENV{SYSTEMD_WANTS}+="devcoredump-save@%k.service"
  '';

  systemd.services.kvm-hid-watch = {
    description = "KVM HIDハブのハング検知と自動復旧";
    # 復旧のxhciリセットがハブ再列挙→udev再トリガーを誘発するため、
    # 復旧不能な場合に無限リセットループへ陥らないよう起動回数を制限する。
    # 復旧成功後の再トリガーは列挙済み判定で何もせず終了するので無害。
    startLimitIntervalSec = 600;
    startLimitBurst = 3;
    serviceConfig = {
      Type = "oneshot";
      # KVM切替後、正常なら全デバイスの列挙は5秒程度で完了する。
      # それを待ってから判定する（正常時は何もしない）。
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
      ExecStart = lib.getExe kvm-hid-reset;
    };
  };

  # ===========================================================================
  # devcoredump の自動退避
  # ===========================================================================
  # kernel 7.2 化（2026-08-22 未明の再起動）以降、amdgpu の GPU ページフォルト
  # → gfx ring timeout でセッションが落ちる事象が同日中に2件発生した（7.1.8
  # 時代の4日間はゼロ件）。上流 (drm/amd) 報告には devcoredump の添付がほぼ
  # 必須だが、カーネルは dump を既定5分で破棄するため手動では間に合わない。
  # udev で生成を検知し /var/lib/devcoredump/ へ即時退避する。
  # 発生が収まって不要になったらルールごと削除してよい。
  systemd.services."devcoredump-save@" = {
    description = "devcoredumpの退避 (%i)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe devcoredump-save} %i";
    };
  };

  # ===========================================================================
  # システムバージョン
  # ===========================================================================
  # NixOSの互換性バージョン。初回インストール時のバージョンを維持。
  # アップグレード時も変更しないこと（データ移行の問題を避けるため）
  system.stateVersion = "26.05";
}
