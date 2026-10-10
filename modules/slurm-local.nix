# =============================================================================
# 1 台だけの Slurm（重い計算の待ち行列）
# =============================================================================
# 管理（slurmctld）と計算（slurmd）を同じマシンで動かし、OpenMC や NJOY のような重い
# 計算を待ち行列で 1 本ずつ流す。全コアを使うジョブは `sbatch --exclusive` で投げると、
# 前のジョブが終わるまで待つ。
#
# 使い方の例:
#   sbatch --exclusive --wait --export=ALL --wrap='<コマンド>'   # 終わるまで待つ
#   squeue                                                      # 待ち行列を見る
#   scancel <ジョブ番号>                                         # 取り消す
#
# --export=ALL は、nix の開発シェルの PATH などをジョブに渡すため（slurmd は systemd から
# 起動され、利用者のシェルの環境を持たない）。
# =============================================================================
{
  config,
  pkgs,
  ...
}:

let
  hostName = config.networking.hostName;
  keyFile = config.services.munge.password;
in
{
  services.slurm = {
    server.enable = true;
    client.enable = true;
    clusterName = hostName;
    controlMachine = hostName;
    # メモリは消費する資源として数えない（CR_Core）ので、RealMemory は目安。OS の分を残す
    nodeName = [
      "${hostName} CPUs=32 Sockets=1 CoresPerSocket=16 ThreadsPerCore=2 RealMemory=86000 State=UNKNOWN"
    ];
    partitionName = [ "main Nodes=${hostName} Default=YES MaxTime=INFINITE State=UP" ];
    extraConfig = ''
      SelectType=select/cons_tres
      SelectTypeParameters=CR_Core
      # 再起動やスリープで slurmd が止まっても、戻ればノードを使える状態にする
      ReturnToService=2
    '';
  };

  # munge の鍵は宣言的に作ると nix のストアに入るので、なければ起動の前に一度だけ作る。
  # 鍵はこのマシンの slurmctld と slurmd の間でしか使わない
  systemd.services.munge-keygen = {
    description = "Create the munge key once";
    wantedBy = [ "munged.service" ];
    before = [ "munged.service" ];
    unitConfig.ConditionPathExists = "!${keyFile}";
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 0700 -o munge -g munge "$(dirname ${keyFile})"
      ${pkgs.munge}/bin/mungekey --create --keyfile=${keyFile}
      chown munge:munge ${keyFile}
      chmod 0400 ${keyFile}
    '';
  };
}
