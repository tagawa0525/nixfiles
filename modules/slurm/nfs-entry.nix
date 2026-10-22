# r995 の ~/github を、どのホストでも同じパスで見せる入口。ジョブは r995 の上で投入したときの
# パスで走るので、投入するホストのマウント点（./submit.nix）と r995 の symlink（./server.nix）を
# このパスにそろえる。.claude/scripts/slurm-run.sh の既定の入口も同じ値にする。
# hard の NFS が届かないあいだ stat が止まるので、~ から下りるツールが入らないホームの外に置く（docs/adr/0048）
"/mnt/r995/github"
