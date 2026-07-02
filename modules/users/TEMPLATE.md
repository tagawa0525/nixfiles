# 新しいユーザーの追加方法

ユーザーは「ユーザーモジュール（システム定義 + Home Manager 紐付け）」と
「Home Manager 個人設定」の2点で構成される。
ホストの `imports` にユーザーモジュールを追加するだけで、そのホストに
システムユーザー・SSH authorized_keys・Home Manager 設定が揃う。
flake.nix の編集は不要。

## ステップ

1. ユーザーモジュールを作成

   ```bash
   cp modules/users/tagawa.nix modules/users/<username>.nix
   ```

   `modules/users/<username>.nix` を編集:
   - ファイル内の `tagawa` をすべて `<username>` に置換
   - `extraGroups` を必要に応じて調整（wheel を外せば sudo 不可の一般ユーザーになる）

   パスワードはリポジトリに置かない（public リポジトリのためハッシュでも不可）。
   ユーザーはパスワードロック状態で作成されるので、ホスト適用後に root で
   `passwd <username>` を実行して設定する（`users.mutableUsers = true` のため
   以降のパスワードは passwd 管理となり、rebuild で上書きされない）。

2. Home Manager 個人設定を作成

   ```bash
   cp -r modules/home/users/tagawa modules/home/users/<username>
   ```

   `modules/home/users/<username>/default.nix` を編集:
   - コメントを適切に更新
   - 必要に応じて `../../parts/` の import を追加・削除

3. SSH 公開鍵を配置

   ```bash
   cp ~/.ssh/id_ed25519.pub modules/home/users/<username>/keys/<hostname>.pub
   ```

   - ファイル名は接続元ホスト名（例: `t14g4.pub`, `r995.pub`）を使う
   - `keys/` 配下の `.pub` はユーザーモジュールが自動で
     authorized_keys（`/etc/ssh/authorized_keys.d/<username>`）に集約する

4. 住まわせたいホストの `hosts/<hostname>/default.nix` に import を追加

   ```nix
   imports = [
     # ...
     ../../modules/users/<username>.nix # 住人: <username>
   ];
   ```

## ディレクトリ構造

``` text
modules/
├── users/                  # ユーザーモジュール（システム定義 + HM 紐付け）
│   ├── tagawa.nix
│   └── <username>.nix
└── home/
    ├── parts/              # ユーザー間で共有する Home Manager 部品
    │   ├── shell.nix
    │   ├── editors.nix
    │   └── ...
    └── users/              # ユーザーごとの Home Manager 個人設定
        ├── tagawa/
        │   ├── default.nix
        │   └── keys/
        │       ├── t14g4.pub
        │       └── r995.pub
        └── <username>/
            ├── default.nix
            └── keys/
                └── <hostname>.pub
```
