# =============================================================================
# sops-nix シークレット管理
# =============================================================================
# age 暗号化を使用してシークレットを管理します。
# シークレットは起動時に自動で /run/secrets/ に復号されます。
#
# セットアップ手順:
#   1. age 鍵を生成（各ホストで一度だけ）:
#      sudo mkdir -p /etc/sops/age
#      nix-shell -p age --run "age-keygen -o /etc/sops/age/keys.txt"
#      sudo chmod 600 /etc/sops/age/keys.txt
#
#   2. 公開鍵を取得して .sops.yaml に追加:
#      nix-shell -p age --run "age-keygen -y /etc/sops/age/keys.txt"
#
#   3. secrets/<hostname>.yaml を作成（暗号化）:
#      nix-shell -p sops --run "sops secrets/<hostname>.yaml"
#
# 使用可能なシークレット:
#   - github-runner-token: GitHub Actions セルフホステッドランナー用トークン
# =============================================================================
{ config, ... }:

{
  # age 秘密鍵のパス
  sops.age.keyFile = "/etc/sops/age/keys.txt";

  # ホスト固有のシークレットファイル
  sops.defaultSopsFile = ../secrets/${config.networking.hostName}.yaml;

  # シークレット定義
  sops.secrets.github-runner-token = { };
}
