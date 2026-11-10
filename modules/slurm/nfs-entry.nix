# r995 の ~/github を、どのホストでも同じパスで見せる入口。ジョブは r995 の上で投入したときの
# パスで走るので、投入するホストのマウント点（./submit.nix）と r995 の symlink（./server.nix）を
# このパスにそろえる。.claude/scripts/slurm-run.sh の既定の入口も同じ値にする。
# hard の NFS が届かないあいだ stat が止まるので、~ から下りるツールが入らないホームの外に置く（docs/adr/0048）
# ノート PC のホームの ~/r995/github は、このパスへの symlink（../profiles/laptop-r995-link.nix）。symlink は 1 階層下に
# 置くので、~ で stat するツールは NFS に触れない。パスを変えるときは symlink の先も変わる（docs/adr/0048 の「変更」）
"/mnt/r995/github"
