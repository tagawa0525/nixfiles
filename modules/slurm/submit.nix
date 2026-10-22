# =============================================================================
# r995 の Slurm に投入するだけのホスト（ノート PC）
# =============================================================================
# 命令のツール（sbatch、squeue など）だけを入れ、slurmd は動かさない。ジョブは r995 の上で
# 投入したときのパスで走るので、r995 の ~/github を ~/mnt/r995 に NFS で自動マウントし、その下で
# 投入する（r995 にも同じ ~/mnt/r995 の入口がある。./server.nix）。
# =============================================================================
{ ... }:

{
  imports = [ ./common.nix ];

  services.slurm.enableStools = true;

  # 使うときだけマウントし、しばらく使わなければ外す。書き込みのある作業の場所なので、soft に
  # せず既定の hard にする（soft は読み書きの途中で失敗を返し、データを黙って壊しうる）。
  # r995 に届かないとき（外出先など）は、マウントの待ち時間で打ち切る。
  # hard では、届かないあいだ stat が止まる。$HOME の直下に置くと、$HOME の全エントリを stat する
  # starship などがそこで止まり、ターミナルが開かなくなるので、~/mnt の下に置く（docs/adr/0048）
  fileSystems."/home/tagawa/mnt/r995" = {
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

  # systemd がマウント点を作るときに親を root で作っても、持ち主を tagawa に直す
  systemd.tmpfiles.rules = [ "d /home/tagawa/mnt 0755 tagawa users -" ];
}
