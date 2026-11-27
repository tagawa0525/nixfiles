# =============================================================================
# r995 の Ghidra のヘッドレス解析
# =============================================================================
# Windows の PC（Ghidra 12.2）と同じプロジェクトを開くので、版は 12.2 以上にする。GUI は使わず、
# support/analyzeHeadless を呼ぶスクリプトが GHIDRA_INSTALL_DIR を見る。
# nixpkgs の ghidra は jdk25 を依存に持つ（Ghidra 12.2 は JDK 25 以上でないと起動しない）。JAVA_HOME は、
# そのスクリプトが Ghidra と同じ JDK を使えるように、同じ jdk25 を指す。
#
# 環境変数は r995 のログインシェルにだけ入る。ほかのホストから Slurm に投げたジョブは、投げたホストの環境で走る
# （modules/slurm/common.nix の --export=ALL）ので、Ghidra のジョブは r995 から投げる。
{ lib, pkgs, ... }:

let
  # バッチのスクリプトが python3.13 で呼ぶ。python313 を丸ごと入れると system-path の bin/python3 が
  # 3.14（modules/profiles/base.nix の python3）から 3.13 に替わるので、python3.13 の名前だけを出す
  python313Only = pkgs.runCommand "python3.13-only" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.python313}/bin/python3.13 $out/bin/python3.13
  '';
in
{
  # プロジェクトを Windows の 12.2 と共有するので、12.2 未満の ghidra には評価の時点で失敗させる
  assertions = [
    {
      assertion = lib.versionAtLeast pkgs.ghidra.version "12.2";
      message = "r995 の ghidra は 12.2 以上にする（Windows の PC と同じプロジェクトを開くため）。nixpkgs の版: ${pkgs.ghidra.version}";
    }
  ];

  environment.systemPackages = [
    pkgs.ghidra
    pkgs.jdk25
    python313Only
  ];

  environment.variables = {
    # support/analyzeHeadless がある展開先（bin/ にあるのは起動のラッパーで、ここではない）
    GHIDRA_INSTALL_DIR = "${pkgs.ghidra}/lib/ghidra";
    JAVA_HOME = "${pkgs.jdk25.home}";
  };
}
