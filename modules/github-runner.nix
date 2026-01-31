# =============================================================================
# GitHub Actions Self-hosted Runner
# =============================================================================
# NixOS 公式モジュールを使用した自動セルフホステッドランナー設定
#
# セットアップ手順:
#   1. PAT トークンをファイルに保存（改行なし）:
#      set PAT (gh auth token)
#      echo -n "$PAT" | sudo tee /run/secrets/github-runner-token
#      sudo chmod 600 /run/secrets/github-runner-token
#
#   2. NixOS を再ビルド:
#      rebuild
#
#   3. サービス状態を確認:
#      systemctl status github-runner-pleasanter-rs.service
#      journalctl -u github-runner-pleasanter-rs.service -n 50 -f
#
# 特徴:
#   - NixOS 公式モジュール (services.github-runners) を使用
#   - PAT (Personal Access Token) で認証
#   - DynamicUser を無効化し、専用 github-runner ユーザーで実行
#   - systemd.tmpfiles.rules でディレクトリを宣言的に管理
#   - TimeoutStartSec で IPv6 接続タイムアウトに対応
#
# トークン更新:
#   トークン期限切れ時は `/run/secrets/github-runner-token` を更新してから
#   `systemctl restart github-runner-pleasanter-rs` で再起動
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
