# =============================================================================
# 開発環境の設定
# =============================================================================
# 開発ツール、activation scripts、言語設定など
# Git関連は git.nix を参照
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

  # cc-bar: Claude Code settings.json に statusLine と hooks を設定
  # nixos-rebuild 時にスクリプトのパスを最新のNixストアパスに更新
  home.activation.ccBarSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS="$HOME/.claude/settings.json"
    # Create settings file if it doesn't exist
    if [ ! -f "$SETTINGS" ]; then
      mkdir -p "$(dirname "$SETTINGS")"
      echo '{}' > "$SETTINGS"
    fi
    if [ -f "$SETTINGS" ]; then
      if [ "''${DRY_RUN:-0}" != "1" ]; then
        RELAY="${pkgs.cc-bar}/bin/cc-bar-relay.sh"
        HOOK="${pkgs.cc-bar}/bin/cc-bar-subagent-hook.sh"
        ${pkgs.jq}/bin/jq \
          --arg relay "$RELAY" \
          --arg hook "$HOOK" \
          '.statusLine |= (
             if (. == null or (.type == "command" and (.command | tostring | contains("cc-bar-relay.sh")))) then
               {"type": "command", "command": $relay}
             else
               .
             end
           ) |
           .hooks |= (
             . // {} |
             .SubagentStop |= (
               ( . // [] ) as $arr
               | ( any( $arr[]?.hooks[]?; .type == "command" and (.command | tostring | contains("cc-bar-subagent-hook.sh")) ) ) as $hasCcBar
               | if $hasCcBar then
                   [ $arr[] |
                     if any(.hooks[]?; .type == "command" and (.command | tostring | contains("cc-bar-subagent-hook.sh"))) then
                       .hooks |= (
                         (.hooks // []) |
                         map(
                           if .type == "command" and (.command | tostring | contains("cc-bar-subagent-hook.sh")) then
                             .command = $hook
                           else
                             .
                           end
                         )
                       )
                     else
                       .
                     end
                   ]
                 else
                   $arr + [ { "hooks": [ { "type": "command", "command": $hook } ] } ]
                 end
             )
           )' \
          "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
        echo "cc-bar: Claude Code settings updated"
      else
        $DRY_RUN_CMD echo "cc-bar: (dry run) Claude Code settings would be updated"
      fi
    fi
  '';

  # GitHub CLI 拡張のインストール（gh-pr-review）
  # gh auth が完了している場合のみ実行
  home.activation.ghExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # gh auth が完了しているか確認
    if ${pkgs.gh}/bin/gh auth status &>/dev/null; then
      # gh-pr-review がインストールされていない場合のみインストール
      if ! ${pkgs.gh}/bin/gh extension list 2>/dev/null | grep -q "agynio/gh-pr-review"; then
        $DRY_RUN_CMD ${pkgs.gh}/bin/gh extension install agynio/gh-pr-review
        $DRY_RUN_CMD echo "gh-pr-review extension installed"
      fi
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
