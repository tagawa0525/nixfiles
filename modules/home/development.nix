# =============================================================================
# 開発環境の設定
# =============================================================================
# Git, activation scripts (rustup, npm, claude) など開発ツールの設定
# =============================================================================
{ pkgs, lib, claudeCodeSource ? null, ... }:

{
  # ===========================================================================
  # 開発ツールパッケージ
  # ===========================================================================
  home.packages = with pkgs; [
    llm-agents.claude-code # Claude Code CLI（自動更新）
    llm-agents.opencode # Open Code CLI（自動更新）
    llm-agents.copilot-cli # GitHub Copilot CLI（自動更新）
    mold # 高速リンカー（Rustのコンパイル時間短縮）
    bacon # ファイル監視＆自動ビルド（cargo-watchの代替）
    cargo-nextest # 高速テストランナー
    cargo-expand # マクロ展開確認

    # Python開発ツール
    uv # 高速パッケージマネージャー（pip/venv代替）
    ruff # Linter & Formatter（Flake8、Black、isortの代替）
    python3Packages.pytest # テストフレームワーク

    # Nix品質チェックツール
    nixpkgs-fmt # Formatter（Nixpkgs公式）
    statix # Linter（静的解析）

    # Markdown品質チェックツール
    markdownlint-cli # Linter（スタイルチェック）
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
  # flakeソースの .claude を ~/.claude にコピー（既存ファイルは上書きしない）
  # これにより、Nixで管理された初期設定を提供しつつ、ユーザーが自由に追加・編集可能
  # claudeCodeSourceがnullの場合は何もしない（オプトイン）
  home.activation.claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_DIR="$HOME/.claude"

    # .claude ディレクトリを作成
    mkdir -p "$CLAUDE_DIR"

    ${lib.optionalString (claudeCodeSource != null) ''
      SOURCE_DIR="${claudeCodeSource}/.claude"

      # commands と skills を再帰的にコピー（既存ファイルは上書きしない）
      # --ignore-existing: 既存ファイルを上書きしない（ユーザーのカスタマイズを保護）
      # -a: アーカイブモード（パーミッション等を保持）
      if [ -d "$SOURCE_DIR/commands" ]; then
        ${pkgs.rsync}/bin/rsync -a --ignore-existing "$SOURCE_DIR/commands/" "$CLAUDE_DIR/commands/"
        $DRY_RUN_CMD echo "Claude Code: commands synced to ~/.claude/"
      fi

      if [ -d "$SOURCE_DIR/skills" ]; then
        ${pkgs.rsync}/bin/rsync -a --ignore-existing "$SOURCE_DIR/skills/" "$CLAUDE_DIR/skills/"
        $DRY_RUN_CMD echo "Claude Code: skills synced to ~/.claude/"
      fi

      # ファイルの書き込み権限を確保（Nix storeからコピーしたファイルは読み取り専用のため）
      $DRY_RUN_CMD chmod -R u+w "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills" 2>/dev/null || true
    ''}
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
      webfetch = "allow"; # URLからコンテンツを取得
      websearch = "allow"; # Web検索を実行
      codesearch = "allow"; # コード検索を実行
    };

    autoupdate = true; # 自動アップデート有効化
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
      core.hooksPath = "~/.config/git/hooks"; # グローバルhooksを使用
    };
  };

  # ===========================================================================
  # Git Hooks（グローバル）
  # ===========================================================================
  # プロジェクトローカルの .git/hooks/ があれば優先、なければデフォルトチェック
  xdg.configFile."git/hooks/pre-commit" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # プロジェクトローカルの pre-commit があれば優先実行
      GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
      LOCAL_HOOK="$GIT_DIR/hooks/pre-commit"
      if [ -x "$LOCAL_HOOK" ]; then
        exec "$LOCAL_HOOK" "$@"
      fi

      # pre-commit フレームワークの設定があれば使用
      if [ -f ".pre-commit-config.yaml" ] && command -v pre-commit >/dev/null 2>&1; then
        exec pre-commit run --hook-stage pre-commit "$@"
      fi

      # ========================================
      # デフォルト: ステージされたファイルをチェック
      # ========================================
      STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)
      [ -z "$STAGED_FILES" ] && exit 0

      check_failed=0

      # Nix ファイルのチェック
      NIX_FILES=$(echo "$STAGED_FILES" | grep '\.nix$' || true)
      if [ -n "$NIX_FILES" ] && command -v nixpkgs-fmt >/dev/null 2>&1; then
        echo "🔍 Checking Nix format..."
        if ! echo "$NIX_FILES" | xargs nixpkgs-fmt --check 2>/dev/null; then
          echo "❌ Nix format check failed. Run: nixpkgs-fmt <files>"
          check_failed=1
        fi
      fi

      # Markdown ファイルのチェック
      MD_FILES=$(echo "$STAGED_FILES" | grep '\.md$' || true)
      if [ -n "$MD_FILES" ] && command -v markdownlint >/dev/null 2>&1; then
        echo "🔍 Checking Markdown style..."
        if ! echo "$MD_FILES" | xargs markdownlint 2>/dev/null; then
          echo "❌ Markdown lint failed. Run: markdownlint --fix <files>"
          check_failed=1
        fi
      fi

      # Python ファイルのチェック
      PY_FILES=$(echo "$STAGED_FILES" | grep '\.py$' || true)
      if [ -n "$PY_FILES" ] && command -v ruff >/dev/null 2>&1; then
        echo "🔍 Checking Python format..."
        if ! ruff format --check $PY_FILES 2>/dev/null; then
          echo "❌ Python format check failed. Run: ruff format <files>"
          check_failed=1
        fi
        echo "🔍 Checking Python lint..."
        if ! ruff check $PY_FILES 2>/dev/null; then
          echo "❌ Python lint failed. Run: ruff check --fix <files>"
          check_failed=1
        fi
      fi

      # Rust ファイルのチェック
      RS_FILES=$(echo "$STAGED_FILES" | grep '\.rs$' || true)
      if [ -n "$RS_FILES" ]; then
        if command -v cargo >/dev/null 2>&1 && cargo locate-project &>/dev/null; then
          # Cargo プロジェクト内: cargo fmt を使用（edition は Cargo.toml から取得）
          echo "🔍 Checking Rust format..."
          if ! cargo fmt --check 2>/dev/null; then
            echo "❌ Rust format check failed. Run: cargo fmt"
            check_failed=1
          fi
        elif command -v rustfmt >/dev/null 2>&1; then
          # Cargo プロジェクト外: rustfmt を直接使用（edition 2024）
          echo "🔍 Checking Rust format..."
          if ! echo "$RS_FILES" | xargs rustfmt --edition 2024 --check 2>/dev/null; then
            echo "❌ Rust format check failed. Run: rustfmt --edition 2024 <files>"
            check_failed=1
          fi
        fi
      fi

      exit $check_failed
    '';
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
