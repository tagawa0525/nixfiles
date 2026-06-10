# 新しいホストの追加方法

ホストは `hosts/<hostName>/` ディレクトリを作るだけで flake.nix が自動検出する
（flake.nix の編集は不要）。`networking.hostName` もディレクトリ名から自動設定される。
削除はディレクトリごと削除すればよい。

## ステップ

1. ホストディレクトリを作成

   ```bash
   mkdir hosts/<hostName>
   ```

2. インストール対象マシンで `hardware-configuration.nix` を生成して配置

   ```bash
   nixos-generate-config --show-hardware-config > hosts/<hostName>/hardware-configuration.nix
   ```

3. `hosts/<hostName>/default.nix` を作成（既存ホストをひな形にしてよい）

   ```nix
   {
     imports = [
       ./hardware-configuration.nix
       # ブート: 初期セットアップは boot-initial、Secure Boot 移行後は boot-lanzaboote
       ../../modules/boot-initial.nix
       # 役割: server / desktop / laptop から1つ選ぶ
       ../../modules/profiles/server.nix
       # GUI 開発機（人が GUI で日常的に使う機）なら追加。server には乗せない
       # ../../modules/profiles/workstation.nix
       # 住人: 住まわせるユーザーのモジュールを列挙
       ../../modules/users/tagawa.nix
     ];

     # インストール時の NixOS バージョンを設定し、以後変更しない
     system.stateVersion = "26.05";
   }
   ```

   役割プロファイルの使い分け:

   | プロファイル    | 用途                                                       |
   | --------------- | ---------------------------------------------------------- |
   | server.nix      | headless 常時稼働機（サスペンド無効化）                    |
   | desktop.nix     | 据え置き GUI 機（リモートビルドの builder 側）             |
   | laptop.nix      | バッテリー駆動機（TLP、リモートビルドの client 側）        |
   | workstation.nix | 役割と直交する「GUI 開発機」用途（COSMIC、日本語入力 等）  |

   ベース設定（SSH、Tailscale、Podman、CLI ツール等）は全ホスト共通の
   base.nix が flake.nix 経由で自動適用される。

4. 各ユーザーがこのホスト「へ」SSH 接続するための公開鍵を配置

   ```bash
   # 接続元ホスト名を冠した .pub を置くだけで authorized_keys に自動集約される
   cp ~/.ssh/id_ed25519.pub modules/home/users/<user>/keys/<接続元hostName>.pub
   ```

5. ビルド・適用

   ```bash
   sudo nixos-rebuild switch --flake .#<hostName>
   ```

6. Secure Boot を有効化する場合は、sbctl で鍵を登録後に
   `boot-initial.nix` を `boot-lanzaboote.nix` に差し替えて再適用する
