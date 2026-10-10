# =============================================================================
# Slurm の管理と計算を動かすホスト（r995）
# =============================================================================
# 管理（slurmctld）と計算（slurmd）を動かし、ほかのホストが投入に使うポートと、ジョブの
# 作業の場所を NFS で出す。どちらも Tailscale（tailscale0）だけに開ける。
# =============================================================================
{ ... }:

let
  # ほかのホストに NFS で出す作業の場所と、どのホストでも同じパスで見える入口
  work = "/home/tagawa/github";
  entry = "/home/tagawa/r995";
in
{
  imports = [ ./common.nix ];

  services.slurm = {
    server.enable = true;
    client.enable = true;
  };

  # ほかのホストは ~/r995（= r995 の ~/github）の下で投入する。ジョブは r995 の上で同じ
  # パスで走るので、r995 にも同じ入口を置く。L+ は既にあるディレクトリを中身ごと消すので、
  # 上書きしない L にする（場所がふさがっていれば作らずに残り、手で移せる）
  systemd.tmpfiles.rules = [ "L ${entry} - - - - ${work}" ];

  # Tailscale のアドレス（100.64.0.0/10）だけに出す。UID と GID は全ホストで揃っている
  # （tagawa は 1000、users は 100）ので、sec=sys のまま使う
  services.nfs.server = {
    enable = true;
    exports = ''
      ${work} 100.64.0.0/10(rw,sync,no_subtree_check)
    '';
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    6817 # slurmctld（ほかのホストの sbatch、squeue）
    2049 # NFSv4（ジョブの作業の場所）
  ];
}
