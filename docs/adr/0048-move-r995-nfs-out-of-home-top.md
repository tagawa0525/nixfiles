---
status: accepted
date: 2026-10-22
requires: []
supersedes: []
superseded-by:
issues: ["#439"]
---

# ADR-0048: r995 の作業の場所の NFS を、ホームの直下ではなく ~/mnt/r995 にマウントする

## 背景

ノート PC（x1ng1、t14g4）は r995 の `~/github` を `~/r995` に NFS で自動マウントし、その下で Slurm にジョブを投入する
（`modules/slurm/submit.nix`）。書き込みのある作業の場所なので、マウントは `hard` にしている（2398e6a）。`hard` では、
r995 に届かないあいだ、そのパスへの stat はエラーを返さず、応答が戻るまで止まる。

x1ng1 で、ネットワークにつながっていないとターミナルが開かない（プロンプトが出ない）と報告があった（2026-10-22）。
ターミナルは `$HOME` で fish を起動し、starship がプロンプトを描く。starship はモジュールを決めるためにカレントディレクトリの
全エントリを stat する。`cd ~ && strace -f -e trace=statx starship prompt` で、`statx("/home/tagawa/r995", ...)` が
出ることを確認した（starship 1.27.0、2026-10-22）。fish の起動そのもの、atuin、zoxide、mise、direnv は `~/r995` に触れていない。
マウントしたまま r995 に届かなくなると（外出先、スリープからの復帰）、starship がこの stat で止まる。

また、starship の statx は `AT_NO_AUTOMOUNT` を付けないので、外れていればマウントを起こし、付いていれば autofs の idle の
タイマーを戻す。`$HOME` でプロンプトを描くたびに `x-systemd.idle-timeout=600` が延び、マウントが外れずに残る。

## 検討した案

- 案 A: マウント点をホームの直下から外し、`~/mnt/r995` にする。ジョブは投入したときのパスで r995 の上で走るので、r995 の
  入口も同じパスに移す
- 案 B: ネットワークが切れたら、NetworkManager の dispatcher で強制アンマウント（`umount -f -l`）する。書き込みの途中の
  データを失いうる。`hard` にした理由（データを黙って壊さない）と矛盾する
- 案 C: `soft` に戻す。止まらずに I/O エラーを返すが、読み書きの途中で失敗してデータを壊しうる（2398e6a で退けた理由そのもの）
- 案 D: starship の設定で `~/r995` を避ける。starship にはカレントディレクトリの走査から特定のエントリを外す設定がなく、
  `scan_timeout` はカーネルの中で止まった stat を打ち切れない。ほかのツール（`ls ~`、`eza ~`）も同じく止まる

## 決定と理由

案 A。`hard` の安全性を保ったまま、普段のカレントディレクトリ（`$HOME`）の直下から NFS を外せる。止まるのは
`~/mnt` か `~/mnt/r995` の下にいるときに限られ、予想できる。`$HOME` で stat されるのはローカルの `~/mnt` だけになり、
プロンプトのたびにマウントを起こすことも、idle のタイマーを戻すこともなくなる。

置き場は、ホームの下の `~/mnt` にする。r995 の上でもホームの下に入口を置けて（tmpfiles の symlink）、root の
ディレクトリを足さずに済む。

## 帰結

- 投入の場所が `~/r995` から `~/mnt/r995` に変わる。`slurm-run.sh`、その SKILL.md、グローバルの CLAUDE.md を合わせて直す
- 既にあるホストには古い入口が残る（ノート PC の空の `~/r995`、r995 の symlink `~/r995`）。tmpfiles の `L` は消さないので、
  rebuild した後に手で消す（#439）
- `~/mnt` は tmpfiles の `d` で tagawa の持ち物にする。systemd が自動マウントの点を作るときに親を root で作っても、`d` が
  持ち主を直す

## 確認

- オフラインで、`$HOME` で開いたターミナルにプロンプトが出る
- `cd ~ && strace -f -e trace=statx starship prompt` に、NFS のパスが出ない
