# =============================================================================
# Slurm の管理と計算を動かすホスト（r995）
# =============================================================================
# 管理（slurmctld）と計算（slurmd）を動かし、ほかのホストが投入に使うポートと、ジョブの
# 作業の場所を NFS で出す。どちらも Tailscale（tailscale0）だけに開ける。
# =============================================================================
{ pkgs, ... }:

let
  # ほかのホストに NFS で出す作業の場所と、どのホストでも同じパスで見える入口
  work = "/home/tagawa/github";
  entry = "/home/tagawa/mnt/r995";
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
    # snapshot isolation は、MariaDB 11.6.2 から既定で有効になり、slurmdbd が書き込みの競合で止まるので切る。
    # slurmdbd は unix socket で接続するので、TCP は待ち受けない
    settings.mysqld = {
      innodb_lock_wait_timeout = 900;
      max_allowed_packet = "16M";
      innodb_snapshot_isolation = "OFF";
      skip-networking = true;
    };
  };

  # slurmctld は起動時に slurmdbd に名乗り、slurmdbd は知らないクラスタならその ClusterID で登録する。
  # slurmdbd が応じる前に名乗ると登録されず、記録が送れない（no remote port）。slurmdbd は
  # Type=simple なので、応じるまで起動を終えたことにせず、slurmctld をその後に起こす（docs/adr/0031）
  systemd.services.slurmdbd.postStart = ''
    until sacctmgr -n show cluster >/dev/null 2>&1; do sleep 1; done
  '';
  # slurmdbd が起動に失敗しても slurmctld は起こす（Requisite にしない）。止まるのが記録だけで、計算は止めないため
  systemd.services.slurmctld = {
    after = [ "slurmdbd.service" ];
    wants = [ "slurmdbd.service" ];
  };

  # ほかのホストは ~/mnt/r995（= r995 の ~/github）の下で投入する。ジョブは r995 の上で同じ
  # パスで走るので、r995 にも同じ入口を置く。L+ は既にあるディレクトリを中身ごと消すので、
  # 上書きしない L にする（場所がふさがっていれば作らずに残り、手で移せる）
  systemd.tmpfiles.rules = [
    "d /home/tagawa/mnt 0755 tagawa users -"
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
