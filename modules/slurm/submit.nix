# =============================================================================
# r995 の Slurm に投入するだけのホスト（ノート PC）
# =============================================================================
# 命令のツール（sbatch、squeue など）だけを入れ、slurmd は動かさない。ジョブは r995 の上で
# 投入したときのパスで走るので、r995 の ~/github を /mnt/r995/github（./nfs-entry.nix）に NFS で
# 自動マウントし、その下で投入する（r995 にも同じパスの入口がある。./server.nix）。
# =============================================================================
{ ... }:

{
  imports = [ ./common.nix ];

  services.slurm.enableStools = true;

  # 使うときだけマウントし、しばらく使わなければ外す。書き込みのある作業の場所なので、soft に
  # せず既定の hard にする（soft は読み書きの途中で失敗を返し、データを黙って壊しうる）。
  # r995 に届かないとき（外出先など）は、マウントの待ち時間で打ち切る
  fileSystems.${import ./nfs-entry.nix} = {
    device = "r995:/home/tagawa/github";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=10"
      "_netdev"
    ];
  };
}
