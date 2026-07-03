# =============================================================================
# Nix分散ビルド - クライアント側設定 (ノートPC用)
# =============================================================================
# このモジュールをimportしたホストは、重い Nix ビルドを r995 にオフロードする。
#
# 動作:
#   1. /root/.ssh/nix-remote-builder (秘密鍵) を起動時に自動生成
#   2. このホストの公開鍵が
#      modules/nix-distributed-builds/keys/<hostname>-builder.pub
#      としてリポジトリに登録されたら、自動的に分散ビルドを有効化
#      (鍵未登録 = r995 側で受け付けられない状態なので buildMachines を空にする
#       ことで初回 rebuild の SSH ハングを回避)
#
# 接続先:
#   r995 (Tailscale MagicDNS で Tailnet IP に解決)
#   両ホストで services.tailscale.enable = true (modules/profiles/base.nix)
#
# 初回セットアップ:
#   1. このモジュールを適用 → /root/.ssh/nix-remote-builder.pub が生成される
#      (この段階では buildMachines は空なのでローカルビルドのみで完了する)
#   2. 生成された pub 鍵を keys/<hostname>-builder.pub にコミット
#   3. r995 を nixos-rebuild → authorizedKeys に反映
#   4. クライアントで再度 nixos-rebuild → 分散ビルドが有効化される
#   詳細は docs/nix-distributed-builds.md を参照。
# =============================================================================
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  builderKey = "/root/.ssh/nix-remote-builder";
  builderHost = "r995";
  # このホストの公開鍵が repo に登録されていれば、r995 側で受け付け可能と判断
  # → 分散ビルドを有効化
  # 登録されていなければ buildMachines を空にして初回 rebuild の詰まりを回避
  thisHostKeyFile = "${self}/modules/nix-distributed-builds/keys/${config.networking.hostName}-builder.pub";
  remoteBuilderReady = builtins.pathExists thisHostKeyFile;
in
{
  # r995 のホスト鍵を固定 (MITM 防止 & 初回プロンプトの抑止)
  # /etc/ssh/ssh_host_ed25519_key.pub on r995 (2026-05-24 取得)
  programs.ssh.knownHosts.${builderHost} = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA++HLpzvIneM8Vuf2c8bhpTsTJZW26wcef2LGq+LUEP";
  };

  # nix-daemon (root 実行) 用の SSH 鍵を初回起動時に生成 (冪等)
  # buildMachines の有効/無効に関わらず常に動作する
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
      echo "[nix-remote-builder] この pub 鍵を repo の以下に追加してください:"
      echo "[nix-remote-builder]   modules/nix-distributed-builds/keys/${config.networking.hostName}-builder.pub"
      echo "[nix-remote-builder] その後 r995 と本ホストを再度 nixos-rebuild すれば分散ビルドが有効化されます"
    fi
  '';

  # 公開鍵が登録されている場合のみ分散ビルドを有効化
  # (未登録のまま有効化すると認証失敗のリトライで rebuild が詰まるため)
  nix.distributedBuilds = remoteBuilderReady;
  # bool を直接代入。lib.mkIf は attrset を返すため bool プロパティに使うと
  # 型不整合になる (false 時に {} となる)
  nix.settings.builders-use-substitutes = remoteBuilderReady;
  # ノートPC (低TDP, 冷却制約) でビルドするより r995 (Ryzen 9950X) に全部
  # 投げた方が体感速い。max-jobs=0 でローカルジョブ実行を抑制し、ビルドを
  # 全て r995 にオフロードする。fixed-output derivation など一部はローカルで
  # 走るが、CPU バウンドな大物は完全に r995 行きになる。
  # 鍵未登録時 (remoteBuilderReady=false) は NixOS デフォルトの "auto" に
  # 戻して初回 rebuild が詰まらないようにする。lib.mkIf は使わず if-then-else
  # で書くのは、上の builders-use-substitutes と同様、option 値の型を維持し
  # mkIf の attrset 返却による型不整合リスクを避けるため。
  nix.settings.max-jobs = if remoteBuilderReady then 0 else "auto";
  nix.buildMachines = lib.optionals remoteBuilderReady [
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
