---
type: ADR
status: accepted
date: 2026-11-27
requires: []
supersedes: []
superseded-by:
issues: []
---

# ADR-0084: Windows の PC との共有は、r995 の Samba で tailscale0 にだけ出す

## 背景

NC の解析資料（ゲームのコピー、メモリのダンプ、Ghidra のプロジェクト。数十〜数百 GB の見込み）を、Windows の PC と r995 の
両方から読み書きする。r995 では Ghidra のヘッドレス解析（`hosts/r995/ghidra.nix`）がこれをローカルで読み書きし、
Windows の PC では GUI の Ghidra が同じプロジェクトを開く。ハードリンクを使うので、置く先はハードリンクの使える
ローカルのファイルシステムにする。

r995 は tagawa が 1 人で使う機械で、外部への入口は Tailscale（`tailscale0`）に絞っている。既存の共有は
`modules/slurm/server.nix` の NFSv4 だけで、Slurm のジョブの作業の場所を Linux のホストに `tailscale0` でだけ出す。
Samba は入っていない。Windows の PC では、この NFS の共有を使えない（依頼元のセッションの確認）ので、利用者が、
Windows からは SMB で開くと決めた（2026-11-27）。

## 検討した案

### 案 1: r995 のローカルに置き、Samba で `tailscale0` にだけ出す

r995 の btrfs に `/srv/ncsoft` を置き、Samba の共有 `ncsoft` を `tailscale0` の 445 にだけ開ける。

- 長所: r995 の Ghidra は共有を通らずにローカルで読み書きする。ハードリンクが使える。Windows の標準の SMB クライアントだけで
  開ける（追加のソフトが要らない）
- 短所: r995 に新しい待ち受け（445）と認証の入口が増える。Samba のパスワードが別に要る

### 案 2: Windows に置き、r995 から SMB で開く

- 長所: r995 に待ち受けが増えない
- 短所: r995 の Ghidra が、ネットワーク越しにプロジェクトを読み書きする。ハードリンクは Windows 側の NTFS の制約に従う。
  r995 を計算の本体にする目的に合わない

### 案 3: sshfs か SFTP で Windows から開く

- 長所: 既存の SSH（`hosts/r995/keys/`）の鍵で入れて、新しい待ち受けが増えない
- 短所: Windows に FUSE の実装（WinFsp など）を足す必要がある。依存が増える。エクスプローラーの標準の操作から外れる

### 案 4: Samba を全インターフェイスに開ける

- 長所: 設定が単純
- 短所: LAN にも 445 を出す。r995 の入口を Tailscale に絞る方針に反する。採らない

## 決定と理由

案 1 を採る。ローカルで読み書きする側（r995 の Ghidra）を速く保ち、Windows は標準の SMB で開けるから。待ち受けが増える
短所は、次で抑える。

- 受け付けは `tailscale0` の 445 だけ（ファイアウォール）。Samba の側でも `hosts allow` で Tailscale の IPv4 と IPv6、
  loopback 以外を断り、`hosts deny = ALL` にする
- ゲスト不可、`valid users = tagawa`、SMB2 以上（`server min protocol`）
- `nmbd`（名前解決）と `winbindd`（ドメイン）は止める
- Samba のパスワードは nix に書かない。利用者が r995 で `sudo smbpasswd -a tagawa` を実行して決める
- 共有の中を指すsymlinkは、smbd がサーバー側で辿って Windows に実体として見せる（`follow symlinks` の既定）。
  共有の外を指すものは辿らない（`wide links` の既定の no）
- Windows の読み取り専用の属性は、所有者の書き込みの権限（POSIX の mode）に対応させる（`map readonly = permissions`）。
  NC は、版のフォルダの間でハードリンクにしたファイルを読み取り専用にして、開いて上書きしたときに前の版の中身まで
  変わる事故を防ぐ。`store dos attributes`（既定は yes）が有効だと、属性は xattr にしか入らず `map readonly` が効かない
  （smb.conf(5)）ので、no にする。hidden と system の属性は保存されなくなる。`map archive` は、既定の yes だと
  アーカイブ属性が所有者の実行ビットに対応するので、no にする。xattr を残したまま r995 の側から mode を揃える案は、
  Windows の属性の付け外しと mode が食い違うので採らない。ハードリンクは inode を共有するので、付け外しはほかの版の
  フォルダの同じ中身にも及ぶ（xattr でも同じ）
- r995 の Ghidra が同じファイルをローカルで書き換えるので、`oplocks`、`level2 oplocks`、`smb2 leases` を止める。
  SMB のクライアントの oplock と lease は、ローカルの書き込みでは破られない

### 帰結

- r995 は新しく 445 を待ち受ける。受け付けるのは Tailscale の送信元だけ
- 認証は Samba の tdbsam のパスワード。再インストールや `/var/lib/samba` を消したときは、`smbpasswd -a tagawa` をやり直す
- 置き場所の `/srv/ncsoft` は、btrfs の root（`@root`）にある。`/home` と同じ容量を共有するので、共有の増加は `/` と `/nix` の
  空きを減らす。容量の上限は付けていない
- 所有者の書き込みの権限が無いファイル（導入時に 482,710 件）は、Windows から読み取り専用に見え、上書きできない。
  Windows の属性の付け外しは、`create mask`（0640）の外の mode のビットを落とす
- oplock を止めるので、Windows 側の大きなファイルの読み書きは、キャッシュが効かず遅くなりうる（測っていない）

### 確認

- `testparm` が設定を読めること（`nix flake check` の評価と、`environment.etc."samba/smb.conf"` のビルド）
- 利用者が `smbpasswd -a tagawa` を実行した後、Windows の PC から Tailscale のアドレスで `\\<r995>\ncsoft` を開いて読み書きできること
- Tailscale 以外の経路からは、445 に届かないこと

## 変更

- 2026-11-27: Windows の読み取り専用の属性を所有者の書き込みの権限に対応させる（`store dos attributes = no`、`map readonly = permissions`、
  `map archive = no`）項を、決定と理由に足した。前は、この項が無く、属性は Samba の既定（xattr に保存）だった。NC が、
  ハードリンクにした版の間のファイルを読み取り専用にして上書きの事故を防ぐのに、属性が mode に入る必要があったため。
