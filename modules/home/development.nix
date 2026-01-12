# =============================================================================
# 開発環境の設定
# =============================================================================
# Git, activation scripts (rustup, npm, claude) など開発ツールの設定
# =============================================================================
{ config, pkgs, lib, ... }:

{
  # ===========================================================================
  # アクティベーションスクリプト
  # ===========================================================================
  # nixos-rebuildまたはhome-manager switch時に実行されるスクリプト
  # 初回セットアップや、Nixで管理しにくいツールの設定に使用

  # Rustツールチェーンの初期化（初回のみ実行）
  home.activation.rustup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.rustup/toolchains" ]; then
      ${pkgs.rustup}/bin/rustup default stable
    fi
  '';

  # npmグローバルパッケージ用ディレクトリの設定
  # デフォルトの/usr/libはNixOSでは書き込み不可のため、ホームに変更
  home.activation.npmGlobalDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.npm-global"
    ${pkgs.nodejs}/bin/npm config set prefix "$HOME/.npm-global"
  '';

  # Claude Code（Anthropic製AIコーディングアシスタント）のインストール
  # npmGlobalDirの後に実行される
  home.activation.claudeCode = lib.hm.dag.entryAfter [ "npmGlobalDir" ] ''
    if ! command -v claude &> /dev/null; then
      ${pkgs.nodejs}/bin/npm install -g @anthropic-ai/claude-code
    fi
  '';

  # ===========================================================================
  # パス設定
  # ===========================================================================
  # npmグローバルパッケージへのパスを追加
  home.sessionPath = [ "$HOME/.npm-global/bin" ];

  # ===========================================================================
  # Git設定
  # ===========================================================================
  programs.git = {
    enable = true;
    settings = {
      user.name = "Hiroaki Tagawa";
      user.email = "tagawa0525@gmail.com";
      init.defaultBranch = "main";  # 新規リポジトリのデフォルトブランチ
      pull.rebase = true;           # pull時にrebaseを使用（マージコミットを避ける）
    };
  };

  # deltaでdiffを見やすく表示
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };
}
