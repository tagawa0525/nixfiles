# =============================================================================
# VS Code Server設定（NixOS用）
# =============================================================================
# VS Code Remote SSHでNixOS上のNode.jsバイナリを自動的にパッチします。
# stable版とInsiders版の両方のインストールパスに対応。
# =============================================================================
{ vscode-server, ... }:

{
  imports = [
    # vscode-server は flake = false のソース取得（理由は flake.nix 参照）
    # のため、flake 出力ではなくソースパスからモジュールを直接 import する
    "${vscode-server}/modules/vscode-server/home.nix"
  ];

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
