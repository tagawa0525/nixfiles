# nixfiles

NixOS と home-manager の構成（r995、t14g4、x1ng1）。開発の進め方の指示、スキル、hook は、別のリポジトリ
[claude-harness](https://github.com/tagawa0525/claude-harness) にあり、`~/.claude` に配られる（このファイルは、このリポジトリに
固有のことだけを書く）。

## ハーネスとの関係

- ハーネスは flake input の `claude-harness` で取り込む（`flake.nix`、`modules/home/users/tagawa/default.nix`）。決定は
  `docs/adr/0082-split-claude-harness-into-its-own-repository.md`
- ハーネスを直すのは `~/nix/claude-harness`。マージの後、このリポジトリの main で `nix-rebuild update claude-harness` を
  実行すると、ハーネスの lock だけが進み、全ホストの構成を検証して rebuild する（実行しなくても、毎日 06:30 の自動更新が
  すべての input と一緒に進める）。ハーネスが使う `lsp-det` と `mattpocock-skills` はこのリポジトリの input なので、一緒に
  進めるときは名前を並べる（`nix-rebuild update claude-harness lsp-det`）
- Slurm のパーティションの名前、NFS の入口、`nix-rebuild.sh` の件名と置き場は、ハーネスのスクリプトと hook との約束。
  `modules/home/parts/tests/harness-contract.sh` が確かめる。約束に関わるファイルを変えるコミットと、`nix-rebuild update` が
  実行する。`rebuild`、`update`、`nix-rebuild` という名前も、hook が rebuild として見る約束（機械では確かめていない）

## ホストを足すとき

`hosts/TEMPLATE.md` の手順に加えて、ハーネスを直すホストと、`claude-sync` を引数なしで使うホストでは、既定の場所に
clone する（`git clone git@github.com:tagawa0525/claude-harness.git ~/nix/claude-harness`）。

## 構成の変更

- 構成を変えたら、`nix flake check`（3 ホストの評価）を通す。適用は `nix-rebuild rebuild`
- `rebuild` は、`~/nix/nixfiles` が main にあれば origin/main まで進めてからビルドする（fetch できない、進められない
  ときは止まる。コミットされていない変更は捨てない）。main 以外にあれば、取り込まずにその中身をビルドする。ブランチの変更を
  実機で試すときは `git -C ~/nix/nixfiles switch --detach <ブランチ>` のあと `rebuild` し、終わったら main に戻す（main 以外
  では、毎朝の自動更新が失敗する）
- `flake.lock` を main に直接コミットするのは `nix-rebuild update` だけ
