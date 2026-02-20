# =============================================================================
# 開発環境の設定
# =============================================================================
# 開発ツール、activation scripts、言語設定など
# Git関連は git.nix、Claude Code関連は claude-code.nix を参照
# =============================================================================
{ pkgs, lib, ... }:

{
  # ===========================================================================
  # 開発ツールパッケージ
  # ===========================================================================
  home.packages = with pkgs; [
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
