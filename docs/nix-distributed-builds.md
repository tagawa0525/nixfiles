# Nix分散ビルド (r995 をリモートビルダーに)

ノートPC (t14g4 / x1ng1) で重い Nix ビルドを実行する際、デスクトップ
r995 (Ryzen 9950X) に SSH 経由でオフロードする仕組み。

## アーキテクチャ

```text
  t14g4 ─┐
         ├── ssh (Tailscale) ──→  r995:22 (nix-ssh)  ──→ nix-daemon
  x1ng1 ─┘
```

- **r995**: `modules/nix-distributed-builds/builder.nix` を import
  - `nix-ssh` という専用ユーザーを作成 (システムユーザー、対話シェルは不要)
  - `nix.settings.trusted-users` に `nix-ssh` を追加
- **t14g4 / x1ng1**: `modules/nix-distributed-builds/client.nix` を import
  - `nix.distributedBuilds = true` + `nix.buildMachines` で r995 を登録
  - `/root/.ssh/nix-remote-builder` を初回起動時に自動生成
  - r995 のホスト鍵を `programs.ssh.knownHosts` で固定

接続先のホスト名は `r995`。Tailscale の MagicDNS が Tailnet IP に解決する。

## 初回セットアップ手順

3 ホストの flake が main にマージされている前提。

### 1. クライアント側で鍵を生成 (各ノートPCで)

```sh
# t14g4 / x1ng1 それぞれで
sudo nixos-rebuild switch --flake .#<hostname>
```

activation script が `/root/.ssh/nix-remote-builder` を生成し、公開鍵を
コンソールに表示する。出力例:

```text
[nix-remote-builder] 新しい SSH 鍵を生成しました:
ssh-ed25519 AAAA... root@t14g4 nix-remote-builder
[nix-remote-builder] この pub 鍵を r995 のリポジトリに追加してください:
[nix-remote-builder]   modules/nix-distributed-builds/keys/t14g4-builder.pub
```

公開鍵の中身を控える:

```sh
sudo cat /root/.ssh/nix-remote-builder.pub
```

### 2. 公開鍵をリポジトリに追加

r995 (もしくは作業ホスト) で:

```sh
# t14g4 から
echo 'ssh-ed25519 AAAA... root@t14g4 nix-remote-builder' \
  > modules/nix-distributed-builds/keys/t14g4-builder.pub

# x1ng1 から
echo 'ssh-ed25519 AAAA... root@x1ng1 nix-remote-builder' \
  > modules/nix-distributed-builds/keys/x1ng1-builder.pub

git add modules/nix-distributed-builds/keys/
git commit -m "feat(nix-builder): t14g4 と x1ng1 の root 公開鍵を登録"
```

### 3. r995 に反映

```sh
# r995 上で
sudo nixos-rebuild switch --flake .#r995
```

`nix-ssh` ユーザーの `authorizedKeys` に各クライアントの鍵が登録される。

### 4. 動作確認 (クライアント側で)

```sh
# r995 への SSH 疎通確認
sudo -i ssh -i /root/.ssh/nix-remote-builder nix-ssh@r995 nix --version

# ダミービルドで分散ビルドが動くか確認
nix build --rebuild nixpkgs#hello -L
# → "building ... on ssh-ng://nix-ssh@r995" のような行が出れば成功
```

## 設定の調整

### maxJobs / speedFactor

`modules/nix-distributed-builds/client.nix` で調整:

- `maxJobs = 16`: r995 で同時実行する derivation 数 (CPU 16 コアに合わせて)
- `speedFactor = 4`: ノートPC比でビルダーが何倍速か (Nix のスケジューラへのヒント)

両方を上げると分散ビルドが優先される。下げると小さなジョブはローカルで処理。

### ビルダー側のキャッシュ利用

`nix.settings.builders-use-substitutes = true` で、ビルダー側が
`cache.nixos.org` から直接 substitute を取得する。クライアントから
依存物を全部転送するより効率的。

## トラブルシューティング

### `nix-ssh@r995: Permission denied (publickey)`

- r995 で `modules/nix-distributed-builds/keys/<host>-builder.pub` が
  リポジトリに含まれていて、かつ `nixos-rebuild switch` 済みか確認
- クライアント側 `/root/.ssh/nix-remote-builder` のパーミッションが
  600 で root 所有か確認

### `Host key verification failed`

`programs.ssh.knownHosts` の r995 ホスト鍵が古い可能性。r995 で
`cat /etc/ssh/ssh_host_ed25519_key.pub` し、`client.nix` の `publicKey`
と一致するか確認。一致しない場合は client.nix を更新。

### ビルドが r995 に行かない

Nix は小さな derivation はローカルで処理することがある。明示的に
分散させるには `--max-jobs 0 --builders 'ssh-ng://nix-ssh@r995'` を
付けるか、`nix.settings.max-jobs = 0` でローカルを無効化する
(ローカルは全く使われなくなる点に注意)。

### Tailscale が落ちている

r995 への到達性が失われると分散ビルドは失敗する。`tailscale status`
で疎通確認。当面の回避としてローカルビルドにフォールバックするには
`--builders ''` を付けて `nixos-rebuild` を実行する。
