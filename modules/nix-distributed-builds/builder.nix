# =============================================================================
# Nix分散ビルド - ビルダー側設定 (r995のような高速マシン用)
# =============================================================================
# このモジュールをimportしたホストは、他のホストから SSH 経由で Nix の
# リモートビルドリクエストを受け付ける。
#
# 仕組み:
#   - nix-ssh: ビルド専用のシステムユーザー
#   - クライアント側 root の公開鍵を authorizedKeys に登録
#   - Nix daemon を信頼できるよう trusted-users に追加
#     (substituter, trusted-public-keys 等の上書きを受け付けるため)
#
# 鍵の追加手順:
#   1. クライアント (t14g4 / x1ng1) で client.nix を適用
#      → /root/.ssh/nix-remote-builder が自動生成される
#   2. クライアント側で /root/.ssh/nix-remote-builder.pub を確認
#   3. modules/nix-distributed-builds/keys/<host>-builder.pub に保存
#   4. r995 を nixos-rebuild すれば authorizedKeys に反映
#
# 鍵ファイルが存在しないホストは authorizedKeys から自動的に除外されるため、
# 初回適用時 (まだ鍵がない状態) でも評価エラーにならない。
# =============================================================================
{ lib, pkgs, self, ... }:
let
  keyDir = "${self}/modules/nix-distributed-builds/keys";
  clientHosts = [
    "t14g4"
    "x1ng1"
  ];
  existingKeyFiles = lib.filter builtins.pathExists (
    map (host: "${keyDir}/${host}-builder.pub") clientHosts
  );
in
{
  # ビルド専用のシステムアカウント
  # nologin にすると sshd が接続を拒否するため bash を割り当てる
  # (Nix daemon が `nix-store --serve` を SSH 経由で叩くだけなので
  #  対話シェルとしては使わない)
  users.users.nix-ssh = {
    isSystemUser = true;
    group = "nix-ssh";
    description = "Nix distributed build account";
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keyFiles = existingKeyFiles;
  };
  users.groups.nix-ssh = { };

  # nix-daemon が substituter 指定や trusted-public-keys を受け入れるため
  # ビルダーアカウントを信頼する必要がある
  nix.settings.trusted-users = [ "nix-ssh" ];
}
