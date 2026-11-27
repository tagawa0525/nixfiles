# =============================================================================
# r995 の Ghidra のヘッドレス解析
# =============================================================================
# Windows の PC（Ghidra 12.2）と同じプロジェクトを開くので、版は 12.2 以上にする。GUI は使わず、
# support/analyzeHeadless を呼ぶスクリプトが GHIDRA_INSTALL_DIR を見る。
# nixpkgs の ghidra は jdk25 を依存に持つ（Ghidra 12.2 は JDK 25 以上でないと起動しない）。JAVA_HOME は、
# そのスクリプトが Ghidra と同じ JDK を使えるように、同じ jdk25 を指す。
{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.ghidra
    pkgs.jdk25
    pkgs.python313 # Ghidra を呼ぶバッチのスクリプトの実行用
  ];

  environment.variables = {
    # support/analyzeHeadless がある展開先（bin/ にあるのは起動のラッパーで、ここではない）
    GHIDRA_INSTALL_DIR = "${pkgs.ghidra}/lib/ghidra";
    JAVA_HOME = "${pkgs.jdk25.home}";
  };
}
