# =============================================================================
# r995 の Slurm に投入するだけのホスト（ノート PC）
# =============================================================================
# 命令の道具（sbatch、squeue など）だけを入れ、slurmd は動かさない。ジョブは r995 の上で
# 投入したときのパスで走るので、r995 の ~/github を ~/r995 に NFS で自動マウントし、その下で
# 投入する（r995 にも同じ ~/r995 の入口がある。./server.nix）。
# =============================================================================
{ ... }:

{
  imports = [ ./common.nix ];

  services.slurm.enableStools = true;

  # 使うときだけマウントし、しばらく使わなければ外す。書き込みのある作業の場所なので、soft に
  # せず既定の hard にする（soft は読み書きの途中で失敗を返し、データを黙って壊しうる）。
  # r995 に届かないとき（外出先など）は、マウントの待ち時間で打ち切る
  fileSystems."/home/tagawa/r995" = {
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
