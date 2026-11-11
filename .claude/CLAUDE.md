# nixfiles

NixOS と home-manager の構成（r995、t14g4、x1ng1）。開発の進め方の指示、スキル、hook は、別のリポジトリ
[claude-harness](https://github.com/tagawa0525/claude-harness) にあり、`~/.claude` に配られる（このファイルは、このリポジトリに
固有のことだけを書く）。

## ハーネスとの関係

- ハーネスは flake input の `claude-harness` で取り込む（`flake.nix`、`modules/home/users/tagawa/default.nix`）。決定は
  `docs/adr/0082-split-claude-harness-into-its-own-repository.md`
- ハーネスを直すのは `~/nix/claude-harness`。マージの後、このリポジトリの main で `nix-rebuild update` を実行すると、lock が
  進んで全ホストの構成を検証し、rebuild する（実行しなくても、毎日 06:30 の自動更新が進める）
- Slurm のパーティションの名前、NFS の入口、`nix-rebuild.sh` の件名と置き場は、ハーネスのスクリプトとの約束。変えるときは
  `modules/home/parts/tests/harness-contract.sh` を実行する

## ホストを足すとき

`hosts/TEMPLATE.md` の手順に加えて、ハーネスを直すホストと、`claude-sync` を引数なしで使うホストでは、既定の場所に
clone する（`git clone git@github.com:tagawa0525/claude-harness.git ~/nix/claude-harness`）。

## 構成の変更

- 構成を変えたら、`nix flake check`（3 ホストの評価）を通す。適用は `nix-rebuild rebuild`
- `flake.lock` を main に直接コミットするのは `nix-rebuild update` だけ
