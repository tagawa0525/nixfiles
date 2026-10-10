# =============================================================================
# Slurm の共通設定（r995 で計算し、各ホストから投入する）
# =============================================================================
# 管理（slurmctld）と計算（slurmd）は r995 だけで動かす（./server.nix）。ほかのホストは
# 命令の道具だけを持ち、Tailscale 経由で r995 に投入する（./submit.nix）。全ホストで同じ
# slurm.conf と同じ munge の鍵（secrets/slurm/munge.key を sops で復号したもの）を使う。
#
# 使い方の例（どのホストからでも）:
#   sbatch --exclusive --wait --export=ALL --wrap='<コマンド>'   # 終わるまで待つ
#   squeue                                                      # 待ち行列を見る
#   scancel <ジョブ番号>                                         # 取り消す
#
# ジョブは r995 の上で、投入したときのディレクトリで走る。ほかのホストからは ~/r995
# （r995 の ~/github を NFS で自動マウント）の下で投入する（./submit.nix）。
# --export=ALL は、nix の開発シェルの PATH などをジョブに渡すため。
# =============================================================================
{ config, ... }:

let
  controller = "r995";
in
{
  sops.secrets.munge-key = {
    format = "binary";
    sopsFile = ../../secrets/slurm/munge.key;
    owner = "munge";
    group = "munge";
    mode = "0400";
    # 鍵を替えたら、古い鍵を持ったままの munged が別のホストと認証できなくなるので再起動する
    restartUnits = [ "munged.service" ];
  };
  services.munge.password = config.sops.secrets.munge-key.path;

  services.slurm = {
    clusterName = controller;
    controlMachine = controller;
    # メモリは消費する資源として数えない（CR_Core）ので、RealMemory は目安。OS の分を残す
    nodeName = [
      "${controller} CPUs=32 Sockets=1 CoresPerSocket=16 ThreadsPerCore=2 RealMemory=86000 State=UNKNOWN"
    ];
    partitionName = [ "main Nodes=${controller} Default=YES MaxTime=INFINITE State=UP" ];
    extraConfig = ''
      SelectType=select/cons_tres
      SelectTypeParameters=CR_Core
      # 再起動やスリープで slurmd が止まっても、戻ればノードを使える状態にする
      ReturnToService=2
    '';
  };
}
