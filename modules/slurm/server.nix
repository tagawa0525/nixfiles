# =============================================================================
# Slurm の管理と計算を動かすホスト（r995）
# =============================================================================
# 管理（slurmctld）と計算（slurmd）を動かし、ほかのホストが投入に使うポートと、ジョブの
# 作業の場所を NFS で出す。どちらも Tailscale（tailscale0）だけに開ける。
# =============================================================================
{ config, pkgs, ... }:

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
    # 待った時間の優先度（PriorityWeightAge）と sacct のための accounting（docs/adr/0031）
    dbdserver.enable = true;
  };

  # slurmdbd の DB。slurmdbd は slurm ユーザーになってから接続するので、unix socket の認証で
  # パスワードを置かない（docs/adr/0031）
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    ensureDatabases = [ "slurm_acct_db" ];
    ensureUsers = [
      {
        name = "slurm";
        ensurePermissions."slurm_acct_db.*" = "ALL PRIVILEGES";
      }
    ];
    # slurmdbd が推奨する値のうち、資源を食わないものだけ合わせる。innodb_buffer_pool_size の推奨
    # （4 GiB 以上）は大きなクラスタ向けで、履歴だけの小さな DB には既定のまま置く（docs/adr/0031）
    settings.mysqld = {
      innodb_lock_wait_timeout = 900;
      max_allowed_packet = "16M";
    };
  };

  # slurmctld は、slurmdbd に登録されていないクラスタの記録を送れない（no remote port）。
  # 最初の 1 回だけ登録し、登録済みなら何もしない。slurmdbd は Type=simple なので、応じるまで待つ。
  # slurmctld が再起動しない反映でも走るよう、multi-user.target からも起こす
  systemd.services.slurm-register-cluster = {
    after = [ "slurmdbd.service" ];
    requires = [ "slurmdbd.service" ];
    before = [ "slurmctld.service" ];
    wantedBy = [
      "multi-user.target"
      "slurmctld.service"
    ];
    inherit (config.systemd.services.slurmctld) path;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "slurm";
      TimeoutStartSec = 60;
    };
    script = ''
      until clusters=$(sacctmgr -n -P show cluster format=cluster); do sleep 1; done
      grep -qx ${config.services.slurm.clusterName} <<<"$clusters" ||
        sacctmgr -i add cluster ${config.services.slurm.clusterName}
    '';
  };

  # ほかのホストは ~/r995（= r995 の ~/github）の下で投入する。ジョブは r995 の上で同じ
  # パスで走るので、r995 にも同じ入口を置く。L+ は既にあるディレクトリを中身ごと消すので、
  # 上書きしない L にする（場所がふさがっていれば作らずに残り、手で移せる）
  systemd.tmpfiles.rules = [
    "L ${entry} - - - - ${work}"
    # 終わったジョブの記録（JobCompLoc。common.nix）の置き場。slurmctld は slurm ユーザーで動く
    "d /var/log/slurm 0755 slurm slurm -"
  ];

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
    6819 # slurmdbd（ほかのホストの sacct）
    2049 # NFSv4（ジョブの作業の場所）
  ];
}
