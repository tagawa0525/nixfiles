# r995 の ~/github を、どのホストでも同じパスで見せる入口。ジョブは r995 の上で投入したときの
# パスで走るので、投入するホストのマウント点（./submit.nix）と r995 の symlink（./server.nix）を
# このパスにそろえる。claude-harness の .claude/scripts/slurm-run.sh の既定の入口も同じ値にする
# （modules/home/parts/tests/harness-contract.sh が突き合わせる）。
# hard の NFS が届かないあいだ stat が止まるので、~ から下りるツールが入らないホームの外に置く（docs/adr/0048）
# ホームの ~/r995/github は、このパスへの symlink（../home/parts/r995-link.nix。マウントを宣言したホストだけ）。
# symlink は 1 階層下に置くので、~ で stat するツールは NFS に触れない（docs/adr/0048 の「変更」）。tmpfiles の L は
# 既にある symlink を置き換えないので、パスを変えたら、各ホストの ~/r995/github を手で消して作り直す
"/mnt/r995/github"
