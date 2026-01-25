# =============================================================================
# 開発環境の設定
# =============================================================================
# Git, activation scripts (rustup, npm, claude) など開発ツールの設定
# =============================================================================
{ pkgs, lib, ... }:

{
  # ===========================================================================
  # 開発ツールパッケージ
  # ===========================================================================
  home.packages = with pkgs; [
    llm-agents.claude-code # Claude Code CLI（自動更新）
    llm-agents.opencode # Open Code CLI（自動更新）
    llm-agents.copilot-cli # GitHub Copilot CLI（自動更新）
    mold # 高速リンカー（Rustのコンパイル時間短縮）

    # Python品質チェックツール
    ruff # Linter & Formatter（Flake8、Black、isortの代替）
    python3Packages.pytest # テストフレームワーク

    # Nix品質チェックツール
    nixpkgs-fmt # Formatter（Nixpkgs公式）
    statix # Linter（静的解析）
  ];
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

  # Claude Code グローバル設定の同期
  # nixfilesの .claude を ~/.claude にコピー（既存ファイルは上書きしない）
  # これにより、Nixで管理された初期設定を提供しつつ、ユーザーが自由に追加・編集可能
  home.activation.claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_DIR="$HOME/.claude"
    SOURCE_DIR="/home/tagawa/nix/nixfiles/.claude"

    # .claude ディレクトリを作成
    mkdir -p "$CLAUDE_DIR"

    # commands と skills を再帰的にコピー（既存ファイルは上書きしない）
    # -n: 既存ファイルを上書きしない（ユーザーのカスタマイズを保護）
    # -r: 再帰的にコピー
    if [ -d "$SOURCE_DIR/commands" ]; then
      ${pkgs.rsync}/bin/rsync -a --ignore-existing "$SOURCE_DIR/commands/" "$CLAUDE_DIR/commands/"
      $DRY_RUN_CMD echo "Claude Code: commands synced to ~/.claude/"
    fi

    if [ -d "$SOURCE_DIR/skills" ]; then
      ${pkgs.rsync}/bin/rsync -a --ignore-existing "$SOURCE_DIR/skills/" "$CLAUDE_DIR/skills/"
      $DRY_RUN_CMD echo "Claude Code: skills synced to ~/.claude/"
    fi

    # ファイルの書き込み権限を確保
    $DRY_RUN_CMD chmod -R u+w "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills" 2>/dev/null || true
  '';

  # ===========================================================================
  # Cargo設定（moldリンカー使用）
  # ===========================================================================
  home.file.".cargo/config.toml".text = ''
    [target.x86_64-unknown-linux-gnu]
    linker = "clang"
    rustflags = ["-C", "link-arg=-fuse-ld=mold"]
  '';

  # ===========================================================================
  # OpenCode設定
  # ===========================================================================
  # グローバル設定ファイル（~/.config/opencode/opencode.json）
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    
    # Web Search機能の許可設定
    permission = {
      webfetch = "allow";    # URLからコンテンツを取得
      websearch = "allow";   # Web検索を実行
      codesearch = "allow";  # コード検索を実行
    };
    
    autoupdate = true;       # 自動アップデート有効化
  };

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

      # Rust
      "target/"
      "*.rs.bk"

      # Ruby
      "vendor/bundle/"
      ".bundle/"
      "*.gem"

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
