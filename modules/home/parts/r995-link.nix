# =============================================================================
# ~/r995/github: r995 の ~/github の NFS への入口
# =============================================================================
# r995 の ~/github を NFS でマウントしているホスト（modules/slurm/submit.nix が fileSystems に宣言する）だけに、
# ~/r995/github から /mnt/r995/github（modules/slurm/nfs-entry.nix）を見られる symlink を置く。r995 自身は
# マウントを宣言しないので置かない。
#
# ~/r995 はローカルの実ディレクトリにし、NFS を指す symlink はその 1 階層下に置く。~/r995 そのものを
# symlink にすると、starship が ~ の直下を stat するたびに automount が起動し、r995 に届かないとき
# （外出先など）はプロンプトがマウントの待ち時間のぶん止まる（docs/adr/0048）。
#
# home.file（mkOutOfStoreSymlink）にしない理由: home-manager は activation の衝突の確認と古い世代の整理で、
# リンクを `[[ -e ]]` で先まで辿り、NFS の automount を起こす（force は衝突の確認しか飛ばさない）。
# tmpfiles の L は lstat しか使わず、既にあるものを置き換えない（docs/adr/0048 の「変更」）。
# =============================================================================
{
  lib,
  osConfig,
  ...
}:

let
  entry = import ../../slurm/nfs-entry.nix;
in
{
  systemd.user.tmpfiles.rules = lib.mkIf (osConfig.fileSystems ? ${entry}) [
    "d %h/r995 0755 - - -"
    "L %h/r995/github - - - - ${entry}"
  ];
}
