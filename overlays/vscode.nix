# =============================================================================
# VSCodeバージョン固定オーバーレイ
# =============================================================================
# nixpkgsのVSCodeバージョンを特定のバージョンに固定します。
# nixpkgs-unstableでは頻繁に更新されるため、安定性のために固定。
#
# 新しいバージョンへの更新方法:
# 1. versionを更新
# 2. sha256を空文字列""にして一度ビルドを実行
# 3. エラーメッセージに表示される正しいハッシュをコピーして設定
# =============================================================================
final: prev: {
  vscode = prev.vscode.overrideAttrs (oldAttrs: rec {
    version = "1.108.0";
    src = final.fetchurl {
      url = "https://update.code.visualstudio.com/${version}/linux-x64/stable";
      sha256 = "02fzc7js802iydf1rkrxarn34f15nmqnrg8h6z0jv1y5y46rsk6v";
      name = "vscode-${version}.tar.gz";
    };
  });
}
