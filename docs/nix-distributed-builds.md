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
  - 公開鍵が `keys/<hostname>-builder.pub` として repo に登録済みの場合のみ
    `nix.distributedBuilds = true` + `nix.buildMachines` を有効化
    (`builtins.pathExists` で判定。未登録時は空のまま = 初回 rebuild が
    SSH 認証失敗のリトライで詰まらない)
  - `/root/.ssh/nix-remote-builder` を初回起動時に自動生成
  - r995 のホスト鍵を `programs.ssh.knownHosts` で固定

接続先のホスト名は `r995`。Tailscale の MagicDNS が Tailnet IP に解決する。

## 初回セットアップ手順

3 ホストの flake が main にマージされている前提。

### 設計: chicken-and-egg を避ける

公開鍵が repo に未登録の間は `nix.buildMachines` を空にして
ローカルビルドのみで進行する。鍵が repo の
`modules/nix-distributed-builds/keys/<hostname>-builder.pub` として
登録された瞬間に `builtins.pathExists` が `true` になり、自動的に
分散ビルドが有効化される。これにより「鍵未登録の状態で SSH 認証失敗の
リトライで rebuild が詰まる」現象を回避する。

### 1. クライアント側で鍵を生成 (各ノートPCで)

```sh
# t14g4 / x1ng1 それぞれで
sudo nixos-rebuild switch --flake .#<hostname>
```

この段階ではこのホストの pub 鍵がまだ repo に無いため `buildMachines` は
空 = ローカルビルドのみで進行する。activation script が
`/root/.ssh/nix-remote-builder` を生成し、公開鍵をコンソールに表示する:

```text
[nix-remote-builder] 新しい SSH 鍵を生成しました:
ssh-ed25519 AAAA... root@t14g4 nix-remote-builder
[nix-remote-builder] この pub 鍵を repo の以下に追加してください:
[nix-remote-builder]   modules/nix-distributed-builds/keys/t14g4-builder.pub
```

後で取り出すには:

```sh
sudo cat /root/.ssh/nix-remote-builder.pub
```

### 2. 公開鍵をリポジトリに追加

r995 (もしくは作業ホスト) で:

```sh
# t14g4 で出力された pub 鍵を保存
echo 'ssh-ed25519 AAAA... root@t14g4 nix-remote-builder' \
  > modules/nix-distributed-builds/keys/t14g4-builder.pub

# x1ng1 で出力された pub 鍵を保存
echo 'ssh-ed25519 AAAA... root@x1ng1 nix-remote-builder' \
  > modules/nix-distributed-builds/keys/x1ng1-builder.pub

git add modules/nix-distributed-builds/keys/
git commit -m "feat(nix-builder): t14g4 と x1ng1 の root 公開鍵を登録"
git push
```

### 3. r995 に反映

```sh
# r995 上で
git pull
sudo nixos-rebuild switch --flake .#r995
```

`nix-ssh` ユーザーの `authorizedKeys` に各クライアントの鍵が登録される。

### 4. クライアントで分散ビルドを有効化

```sh
# t14g4 / x1ng1 で
git pull
sudo nixos-rebuild switch --flake .#<hostname>
```

`keys/<hostname>-builder.pub` が repo に存在するので `pathExists` が
`true` となり、`nix.buildMachines` に r995 が登録される。

### 5. 動作確認 (クライアント側で)

```sh
# r995 への SSH 疎通確認
sudo ssh -i /root/.ssh/nix-remote-builder nix-ssh@r995 nix --version

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

まず `modules/nix-distributed-builds/keys/<hostname>-builder.pub` が
repo に存在するか確認 (これが無いと `buildMachines` 自体が空になる)。

それでも分散ビルドにならない場合: Nix は小さな derivation はローカルで
処理することがある。明示的に分散させるには
`--max-jobs 0 --builders 'ssh-ng://nix-ssh@r995'` を付けるか、
`nix.settings.max-jobs = 0` でローカルを無効化する
(ローカルは全く使われなくなる点に注意)。

### 初回 rebuild が詰まる場合 (旧版から移行する場合)

`buildMachines` を無条件で登録していた版を適用してしまった場合、SSH 認証
失敗のリトライで rebuild が進まない。一時的に `--option builders ''` を
付ければビルダー無しで rebuild できる:

```sh
sudo nixos-rebuild switch --flake .#<hostname> --option builders ''
```

そのまま activation script で鍵生成 → 上記セットアップ手順に戻る。

### Tailscale が落ちている

r995 への到達性が失われると分散ビルドは失敗する。`tailscale status`
で疎通確認。当面の回避としてローカルビルドにフォールバックするには
`--builders ''` を付けて `nixos-rebuild` を実行する。
