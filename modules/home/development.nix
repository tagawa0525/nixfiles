# =============================================================================
# 開発環境の設定
# =============================================================================
# Git, activation scripts (rustup, npm, claude) など開発ツールの設定
# =============================================================================
{ pkgs, lib, ... }:

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
    ignores = [
      # Claude Code
      "**/.claude/settings.local.json"

      # direnv
      ".envrc"
      ".direnv/"

      # Python
      "__pycache__/"
      "*.pyc"
      "*.pyo"
      ".venv/"
      ".mypy_cache/"
      ".pytest_cache/"
      ".ruff_cache/"

      # Node.js
      "node_modules/"

      # エディタ/IDE
      ".idea/"
      "*.swp"
      "*.swo"
      "*~"

      # OS
      ".DS_Store"
      "Thumbs.db"

      # 環境変数（機密情報）
      ".env"
      ".env.local"
      ".env*.local"

      # ログ
      "*.log"
    ];
    settings = {
      user.name = "Hiroaki Tagawa";
      user.email = "tagawa0525@gmail.com";
      init.defaultBranch = "main"; # 新規リポジトリのデフォルトブランチ
      pull.rebase = true; # pull時にrebaseを使用（マージコミットを避ける）
    };
  };

  # deltaでdiffを見やすく表示
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  # ===========================================================================
  # GitHub CLI設定
  # ===========================================================================
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
    };
    gitCredentialHelper.enable = true;
  };

  # ===========================================================================
  # htop設定
  # ===========================================================================
  programs.htop = {
    enable = true;
    settings = {
      hide_kernel_threads = true;
      highlight_megabytes = true;
      highlight_threads = true;
      show_program_path = true;
      tree_view = false;
    };
  };
}
