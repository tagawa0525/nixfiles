# =============================================================================
# GitHub Actions Self-hosted Runner
# =============================================================================
# Podman でコミュニティ GitHub Runner イメージを実行
# (NixOS 公式モジュールの systemd namespace エラーを回避)
#
# セットアップ手順:
#   1. トークンを取得:
#      gh api repos/tagawa0525/pleasanter-rs/actions/runners/registration-token -X POST --jq '.token'
#
#   2. secret ファイルを作成:
#      sudo mkdir -p /run/secrets
#      echo "<TOKEN>" | sudo tee /run/secrets/gh_runner_token
#      sudo chmod 600 /run/secrets/gh_runner_token
#
#   3. ワーキングディレクトリを作成:
#      mkdir -p ~/github-runner
#
#   4. NixOS を再ビルド:
#      sudo nixos-rebuild switch --flake ~/nix/nixfiles#r995
#
#   5. Podman コンテナを起動:
#      systemctl start podman-github-runner.service
#
# =============================================================================
{ config, pkgs, ... }:

{
  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers.github-runner = {
      # myoung34/github-runner: 最も人気のあるコミュニティ実装
      # 注記: agenix や他の秘密管理システムを組み込むまで、手動起動としています
      image = "docker.io/myoung34/github-runner:latest";
      autoStart = false;

      environment = {
        RUNNER_NAME = config.networking.hostName;
        REPO_URL = "https://github.com/tagawa0525/pleasanter-rs";
        RUNNER_WORKDIR = "/tmp/runner";
        RUNNER_LABELS = "nixos";
        DISABLE_AUTO_UPDATE = "true";
      };

      volumes = [
        "/var/lib/github-runner:/var/lib/github-runner:rw"
        "/run/podman/podman.sock:/var/run/docker.sock:rw" # Docker-in-Podman
      ];

      extraOptions = [
        "--memory=2g"
        "--cpus=2"
      ];
    };
  };
}
