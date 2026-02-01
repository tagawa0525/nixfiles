# =============================================================================
# GitHub Actions Self-hosted Runner
# =============================================================================
# NixOS 公式モジュールを使用した自動セルフホステッドランナー設定
#
# トークン管理:
#   sops-nix で管理。secrets/<hostname>.yaml の github-runner-token に設定。
#   再起動時に自動で /run/secrets/github-runner-token に復号される。
#
# トークン更新手順:
#   1. 新しい PAT を取得:
#      gh auth token
#
#   2. secrets/<hostname>.yaml を編集:
#      nix-shell -p sops --run "sops secrets/<hostname>.yaml"
#
#   3. サービスを再起動:
#      systemctl restart github-runner-pleasanter-rs
#
# サービス確認:
#   systemctl status github-runner-pleasanter-rs.service
#   journalctl -u github-runner-pleasanter-rs.service -n 50 -f
#
# 特徴:
#   - NixOS 公式モジュール (services.github-runners) を使用
#   - sops-nix で PAT (Personal Access Token) を管理
#   - DynamicUser を無効化し、専用 github-runner ユーザーで実行
#   - systemd.tmpfiles.rules でディレクトリを宣言的に管理
#   - TimeoutStartSec で IPv6 接続タイムアウトに対応
# =============================================================================
{ config, pkgs, ... }:

{
  # github-runner ユーザーとグループを作成
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
  };

  users.groups.github-runner = { };

  services.github-runners = {
    pleasanter-rs = {
      enable = true;
      url = "https://github.com/tagawa0525/pleasanter-rs";
      name = config.networking.hostName;
      tokenFile = "/run/secrets/github-runner-token";
      replace = true; # 同名ランナーを自動置換

      # DynamicUser を無効化
      user = "github-runner";
      group = "github-runner";

      # ラベル
      extraLabels = [ "nixos" ];

      # Docker/Podman サポート
      extraPackages = with pkgs; [ podman docker ];

      extraEnvironment = {
        DOCKER_HOST = "unix:///run/user/1000/podman/podman.sock";
      };

      # systemd セキュリティ設定の調整
      # IPv6 タイムアウト問題への対応
      serviceOverrides = {
        TimeoutStartSec = 300;
      };
    };
  };

  # ディレクトリを NixOS で宣言的に管理
  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner/pleasanter-rs 0750 github-runner github-runner - -"
    "d /var/log/github-runner/pleasanter-rs 0750 github-runner github-runner - -"
  ];

  # IPv6 無効化（オプション: GitHub サーバーの接続タイムアウト対策）
  # networking.enableIPv6 = false;
}
