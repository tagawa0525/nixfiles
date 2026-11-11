# =============================================================================
# Claude のアプリケーション
# =============================================================================
# Claude Code CLI と Claude Desktop の本体。どの版を入れるかは PC の構成で、nixfiles の flake.lock の llm-agents の
# rev が決める（pkgs.llm-agents は flake.nix の overlay）。~/.claude の中身と hook（ハーネス）は claude-code.nix
# =============================================================================
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    llm-agents.claude-code # Claude Code CLI（自動更新）
    # Anthropic 公式の Linux 版 deb（downloads.claude.ai の APT）を展開したもの
    llm-agents.claude-desktop # Claude Desktop（GUI、自動更新）
    # Cowork の VM が PATH から探す。同梱せず利用側で用意する設計
    # （同梱すると closure が約 0.8 GiB 増える。上流 llm-agents.nix の claude-desktop）
    qemu
  ];
}
