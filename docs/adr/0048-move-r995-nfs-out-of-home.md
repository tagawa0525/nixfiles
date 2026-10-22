---
status: accepted
date: 2026-10-22
requires: []
supersedes: []
superseded-by:
issues: ["#439"]
---

# ADR-0048: r995 の作業の場所の NFS を、ホームの外の /mnt/r995/github にマウントする

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

- 案 A: マウント点をホームの外の `/mnt/r995/github` にする。ジョブは投入したときのパスで r995 の上で走るので、r995 の
  入口も同じパスの symlink にする
- 案 A': マウント点をホームの下の `~/mnt/r995` や `~/r995/github` にする。`$HOME` の直下で stat されるのはローカルの
  ディレクトリになり、starship の件は直る。いったん `~/mnt/r995` で実装したが、ローカルのレビューで、`~` から再帰的に下りる
  ツール（`fd`、`rg`、`find`、`du`、エディタのファイル監視）が NFS に入り、オフラインで止まるとの指摘を受けて退けた
  （2026-10-22）
- 案 B: ネットワークが切れたら、NetworkManager の dispatcher で強制アンマウント（`umount -f -l`）する。書き込みの途中の
  データを失いうる。`hard` にした理由（データを黙って壊さない）と矛盾する
- 案 C: `soft` に戻す。止まらずに I/O エラーを返すが、読み書きの途中で失敗してデータを壊しうる（2398e6a で退けた理由そのもの）
- 案 D: starship の設定で `~/r995` を避ける。starship にはカレントディレクトリの走査から特定のエントリを外す設定がなく、
  `scan_timeout` はカーネルの中で止まった stat を打ち切れない。ほかのツール（`ls ~`、`eza ~`）も同じく止まる

## 決定と理由

案 A。`hard` の安全性を保ったまま、NFS をホームの外に出せる。`~` で stat するツールにも、`~` から再帰的に下りるツールにも
NFS は見えず、止まるのは `/mnt/r995` とその下を触ったときに限られる。`/mnt` は、一時的にマウントするファイルシステムの
置き場として FHS の慣習に合う。末尾を `github` にして、r995 の上の実体（`~/github`）と名前をそろえる。

パスは `modules/slurm/nfs-entry.nix` の 1 か所で定め、投入するホストのマウント点（`submit.nix`）と r995 の symlink
（`server.nix`）がずれないようにする。

## 帰結

- 投入の場所が `~/r995` から `/mnt/r995/github` に変わる。`slurm-run.sh` の既定の入口（`SLURM_RUN_NFS_ENTRY` で
  テストから置き換える）、その SKILL.md、グローバルの CLAUDE.md を合わせて直す。`slurm-run.sh` は Nix の外で配るので、
  既定の値は `nfs-entry.nix` と手でそろえる
- 既にあるホストには古い入口が残る（ノート PC の空の `~/r995`、r995 の symlink `~/r995`）。tmpfiles の `L` は消さないので、
  rebuild した後に手で消す。古いパスで投入して待っているジョブが無いことを先に確かめる（#439）
- 移すときの switch は旧マウントのユニットを止める。r995 に届かないまま `hard` の旧マウントが残っていると、そのアンマウントで
  switch が止まるので、r995 に届く状態で先に `~/r995` を外す（#439）
- パスを鍵にした状態は引き継がれない。zoxide の記録、direnv の allow（`direnv allow` をやり直す）、Claude Code の
  プロジェクトごとの記録（`~/.claude/projects/` の下）

## 確認

- オフラインで、`$HOME` で開いたターミナルにプロンプトが出る
- `cd ~ && strace -f -e trace=statx starship prompt` に、NFS のパスが出ない
