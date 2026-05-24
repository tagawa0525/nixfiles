# =============================================================================
# Nix分散ビルド - クライアント側設定 (ノートPC用)
# =============================================================================
# このモジュールをimportしたホストは、重い Nix ビルドを r995 にオフロードする。
#
# 動作:
#   1. /root/.ssh/nix-remote-builder (秘密鍵) を起動時に自動生成
#   2. nix.distributedBuilds で r995 を nix.buildMachines に登録
#   3. nix-build / nixos-rebuild が r995 でビルドを実行
#      (maxJobs に達した derivation, supportedFeatures の一致など条件あり)
#
# 接続先:
#   r995 (Tailscale MagicDNS で Tailnet IP に解決)
#   両ホストで services.tailscale.enable = true (modules/common.nix)
#
# 初回セットアップ:
#   このモジュールを適用後、生成された /root/.ssh/nix-remote-builder.pub を
#   このリポジトリの modules/nix-distributed-builds/keys/<host>-builder.pub
#   に追加して r995 で nixos-rebuild する。
#   詳細は docs/nix-distributed-builds.md を参照。
# =============================================================================
{ config, pkgs, ... }:
let
  builderKey = "/root/.ssh/nix-remote-builder";
  builderHost = "r995";
in
{
  # r995 のホスト鍵を固定 (MITM 防止 & 初回プロンプトの抑止)
  # /etc/ssh/ssh_host_ed25519_key.pub on r995 (2026-05-24 取得)
  programs.ssh.knownHosts.${builderHost} = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA++HLpzvIneM8Vuf2c8bhpTsTJZW26wcef2LGq+LUEP";
  };

  # nix-daemon (root 実行) 用の SSH 鍵を初回起動時に生成 (冪等)
  system.activationScripts.nixRemoteBuilderKey.text = ''
    if [ ! -e ${builderKey} ]; then
      mkdir -p /root/.ssh
      chmod 700 /root/.ssh
      ${pkgs.openssh}/bin/ssh-keygen -t ed25519 \
        -f ${builderKey} \
        -N "" \
        -C "root@${config.networking.hostName} nix-remote-builder" \
        -q
      echo "[nix-remote-builder] 新しい SSH 鍵を生成しました:"
      cat ${builderKey}.pub
      echo "[nix-remote-builder] この pub 鍵を r995 のリポジトリに追加してください:"
      echo "[nix-remote-builder]   modules/nix-distributed-builds/keys/${config.networking.hostName}-builder.pub"
    fi
  '';

  # 分散ビルド設定
  nix.distributedBuilds = true;
  # ビルダー側で cache.nixos.org からの substitution を許可
  # (依存をクライアントから転送する代わりにビルダーが自前で取得)
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName = builderHost;
      sshUser = "nix-ssh";
      sshKey = builderKey;
      systems = [ "x86_64-linux" ];
      # Nix 2.4+ の改善プロトコル (ssh-ng) で転送効率が向上
      protocol = "ssh-ng";
      # Ryzen 9950X = 16C/32T。並列ビルドが暴走しないよう抑えめ
      maxJobs = 16;
      # ノートPC比でおおよそ 4 倍の処理能力 (Nix のスケジューラへのヒント)
      speedFactor = 4;
      supportedFeatures = [
        "kvm"
        "big-parallel"
        "nixos-test"
        "benchmark"
      ];
    }
  ];
}
