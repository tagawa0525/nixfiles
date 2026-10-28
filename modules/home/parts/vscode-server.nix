# =============================================================================
# VS Code Server設定（NixOS用）
# =============================================================================
# VS Code Remote SSHでNixOS上のNode.jsバイナリを自動的にパッチします。
# stable版とInsiders版の両方のインストールパスに対応。
# =============================================================================
{ pkgs, vscode-server, ... }:

{
  imports = [
    vscode-server.homeModules.default
  ];

  services.vscode-server = {
    enable = true;
    # 同梱のnodeをpatchelfで書き換えるとsegfaultする（新しいpatchelfの不具合）ため、
    # nixpkgsのnodeで起動する。メジャー版はVS Code同梱のnodeに合わせる。
    nodejsPackage = pkgs.nodejs_24;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
