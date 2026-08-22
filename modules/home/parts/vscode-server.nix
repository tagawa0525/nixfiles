# =============================================================================
# VS Code Server設定（NixOS用）
# =============================================================================
# VS Code Remote SSHでNixOS上のNode.jsバイナリを自動的にパッチします。
# stable版とInsiders版の両方のインストールパスに対応。
# =============================================================================
{ vscode-server, ... }:

{
  imports = [
    vscode-server.homeModules.default
  ];

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
