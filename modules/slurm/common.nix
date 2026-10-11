# =============================================================================
# Slurm の共通設定（r995 で計算し、各ホストから投入する）
# =============================================================================
# 管理（slurmctld）と計算（slurmd）は r995 だけで動かす（./server.nix）。ほかのホストは
# 命令の道具だけを持ち、Tailscale 経由で r995 に投入する（./submit.nix）。全ホストで同じ
# slurm.conf と同じ munge の鍵（secrets/slurm/munge.key を sops で復号したもの）を使う。
#
# 使い方の例（どのホストからでも）:
#   ~/.claude/scripts/slurm-run.sh -t <見積もり> <名前> '<コマンド>'   # 投げて終わるまで待つ
#   squeue                                                            # 待ち行列を見る
#   scontrol top <ジョブ番号>                                          # 待っている自分のジョブを先頭へ
#   scancel <ジョブ番号>                                               # 取り消す
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

  # squeue の既定の表示に、名前、CPU 数（%C）、優先度（%Q）、経過、見積もり（%l）、始まりの見込み（%S）、
  # 連絡先（%k）を出す。優先度は scontrol top と nice で下がった分を読むため（docs/adr/0030）
  environment.variables.SQUEUE_FORMAT = "%.6i %.24j %.8T %.5C %.8Q %.10M %.10l %.19S %k";

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
      # 利用者が待っている自分のジョブの順番を変えられるようにする（scontrol top。docs/adr/0007）
      SchedulerParameters=enable_user_top
      # 優先度を「10000 + 待った分 − nice」にする。投げた順に走り、scontrol top が付けた nice は何分ぶん
      # 後ろに回したかの意味になる。基礎は、投げたばかりのジョブを優先度 1 にしないため（scontrol top は
      # 優先度 1 のジョブを下げる対象から外す）。Age の重みは PriorityMaxAge の既定（7 日 = 10080 分）と同じ数で、
      # 1 分に 1 上がる。パーティションが 1 つで PriorityJobFactor が既定の 1 であることを前提にする（docs/adr/0030）
      PriorityWeightPartition=10000
      PriorityWeightAge=10080
      PriorityCalcPeriod=1
      # --time は待ち行列の見込みのための見積もりとして使い、超えても止めない（docs/adr/0007）
      OverTimeLimit=UNLIMITED
      # 終わったジョブを 1 行ずつ書き、見積もり（TimeLimit）と実際の時間を後から読めるようにする（docs/adr/0017）。
      # 書くのは slurmctld だけで、置き場は ./server.nix の tmpfiles。slurm.conf は全ホストで同じにする
      # accounting は r995 の slurmdbd に置く（docs/adr/0031）
      AccountingStorageType=accounting_storage/slurmdbd
      AccountingStorageHost=${controller}
      # ジョブのメモリと CPU の使用量を集め、sacct の MaxRSS などに残す
      JobAcctGatherType=jobacct_gather/linux
      JobCompType=jobcomp/filetxt
      JobCompLoc=/var/log/slurm/job_completions
    '';
  };
}
