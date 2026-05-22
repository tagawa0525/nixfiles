# 新しいユーザーの追加方法

## ステップ

1. ユーザーディレクトリを作成

   ```bash
   cp -r modules/home/users/tagawa modules/home/users/<username>
   ```

2. `modules/home/users/<username>/default.nix` を編集
   - コメントを適切に更新
   - 必要に応じて import を追加・削除

3. `modules/home/users/<username>/ssh.nix` を編集
   - authorized_keys を設定

4. flake.nix を編集

   ```nix
   home-manager.users.<username> = import ./modules/home/users/<username>/default.nix;
   ```

5. `hosts/r995/default.nix` にユーザーを追加

   ```nix
   users.users.<username>.openssh.authorizedKeys.keyFiles = [
     "${self}/keys/<username>@r995.pub"
   ];
   ```

6. SSH 公開鍵を配置

   ```bash
   cp ~/.ssh/id_ed25519.pub keys/<username>@r995.pub
   ```

## ディレクトリ構造

``` text
modules/home/
├── common/
│   ├── shell.nix
│   ├── editors.nix
│   └── ...
└── users/
    ├── tagawa/
    │   ├── default.nix
    │   └── ssh.nix
    └── <username>/
        ├── default.nix
        └── ssh.nix
```
