# =============================================================================
# 開発環境の設定
# =============================================================================
# 開発ツール、activation scripts、言語設定など
# Git関連は git.nix を参照
# =============================================================================
{ pkgs, lib, claudeCodeSource ? null, ... }:

let
  # グローバルに登録する Claude Code hooks
  # nixos-rebuild 時に ~/.claude/settings.json へ自動登録される
  claudeGlobalHooks = [
    { file = "block-main-commit.sh"; matcher = "Bash"; timeout = 10000; }
    { file = "pre-merge-check.sh"; matcher = "Bash"; timeout = 30000; }
  ];

  # Claude Code settings.json の静的設定
  # nixos-rebuild 時に ~/.claude/settings.json へ自動反映される
  # hooks, statusLine, skipDangerousModePermissionPrompt は別途管理
  claudeCodeStaticSettings = {
    permissions = {
      allow = [
        # Skills
        "Skill(git-commit)"
        "Skill(git-branch)"
        "Skill(git-worktree)"
        "Skill(git-push)"
        "Skill(git-tidy)"
        "Skill(git-cherry-pick)"
        "Skill(git-info)"
        "Skill(gh-pr-merge)"
        "Skill(gh-pr-create)"
        "Skill(gh-pr-review)"
        "Skill(gh-actions-check)"
        # Git
        "Bash(git add:*)"
        "Bash(git branch:*)"
        "Bash(git checkout:*)"
        "Bash(git cherry-pick:*)"
        "Bash(git clean:*)"
        "Bash(git clone:*)"
        "Bash(git commit:*)"
        "Bash(git config:*)"
        "Bash(git diff:*)"
        "Bash(git diff-tree:*)"
        "Bash(git fetch:*)"
        "Bash(git log:*)"
        "Bash(git merge:*)"
        "Bash(git mv:*)"
        "Bash(git pull:*)"
        "Bash(git push:*)"
        "Bash(git rebase:*)"
        "Bash(git remote:*)"
        "Bash(git reset:*)"
        "Bash(git restore:*)"
        "Bash(git rev-list:*)"
        "Bash(git rm:*)"
        "Bash(git show:*)"
        "Bash(git stash:*)"
        "Bash(git status:*)"
        "Bash(git submodule:*)"
        "Bash(git switch:*)"
        "Bash(git symbolic-ref:*)"
        "Bash(git tag:*)"
        "Bash(git worktree:*)"
        # GitHub CLI
        "Bash(gh api:*)"
        "Bash(gh auth:*)"
        "Bash(gh pr:*)"
        "Bash(gh release:*)"
        "Bash(gh repo:*)"
        "Bash(gh run:*)"
        "Bash(gh workflow:*)"
        # Nix
        "Bash(nix search:*)"
        "Bash(nix build:*)"
        "Bash(nix eval:*)"
        "Bash(nix flake:*)"
        "Bash(nix-build:*)"
        "Bash(nix-instantiate:*)"
        "Bash(nix-prefetch-url:*)"
        "Bash(nixpkgs-fmt:*)"
        "Bash(statix:*)"
        # 言語ツール
        "Bash(cargo:*)"
        "Bash(rustc:*)"
        "Bash(rustup:*)"
        "Bash(markdownlint:*)"
        "Bash(python3:*)"
        "Bash(node:*)"
        "Bash(npx:*)"
        # システム
        "Bash(systemctl:*)"
        "Bash(journalctl:*)"
        "Bash(mount:*)"
        "Bash(chmod:*)"
        "Bash(fish:*)"
        "Bash(direnv:*)"
        "Bash(podman:*)"
        "Bash(podman-compose:*)"
        # ユーティリティ
        "Bash(sort:*)"
        "Bash(echo:*)"
        "Bash(cat:*)"
        "Bash(file:*)"
        "Bash(test:*)"
        "Bash(grep:*)"
        "Bash(ls:*)"
        "Bash(tree:*)"
        "Bash(find:*)"
        "Bash(wc:*)"
        "Bash(jq:*)"
        "Bash(xargs:*)"
        "Bash(curl:*)"
        "Bash(hash:*)"
        "Bash(env)"
        # gh-pr-review スキルスクリプト
        "Bash(~/.claude/skills/gh-pr-review/scripts/get-pr-info.sh:*)"
        "Bash(~/.claude/skills/gh-pr-review/scripts/get-review-comments.sh:*)"
        "Bash(~/.claude/skills/gh-pr-review/scripts/reply-to-comment.sh:*)"
        "Bash(~/.claude/skills/gh-pr-review/scripts/resolve-thread.sh:*)"
        # Web
        "WebFetch(domain:api.github.com)"
        "WebFetch(domain:claude.ai)"
        "WebFetch(domain:code.visualstudio.com)"
        "WebFetch(domain:crates.io)"
        "WebFetch(domain:discourse.nixos.org)"
        "WebFetch(domain:docs.rs)"
        "WebFetch(domain:hub.docker.com)"
        "WebFetch(domain:gist.github.com)"
        "WebFetch(domain:github.com)"
        "WebFetch(domain:lib.rs)"
        "WebFetch(domain:mynixos.com)"
        "WebFetch(domain:nix-community.github.io)"
        "WebFetch(domain:raw.githubusercontent.com)"
        "WebFetch(domain:search.nixos.org)"
        "WebFetch(domain:www.anthropic.com)"
        "WebSearch"
      ];
      deny = [ "Bash(sudo:*)" ];
      defaultMode = "default";
    };
    enabledPlugins = {
      "code-simplifier@claude-plugins-official" = true;
      "rust-analyzer-lsp@claude-plugins-official" = true;
    };
    language = "Japanese";
    autoUpdatesChannel = "stable";
    plansDirectory = "docs/plans";
  };
in
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

      if [ -d "$SOURCE_DIR/hooks" ]; then
        ${pkgs.rsync}/bin/rsync -a --ignore-existing "$SOURCE_DIR/hooks/" "$CLAUDE_DIR/hooks/"
        $DRY_RUN_CMD echo "Claude Code: hooks synced to ~/.claude/"
      fi

      # ファイルの書き込み権限を確保（Nix storeからコピーしたファイルは読み取り専用のため）
      $DRY_RUN_CMD chmod -R u+w "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks" 2>/dev/null || true
    ''}

    # 静的設定と hooks を settings.json に反映
    # claudeCodeSource の有無に関わらず常に実行（宣言的管理を保証）
    SETTINGS="$CLAUDE_DIR/settings.json"
    if [ ! -f "$SETTINGS" ]; then
      echo '{}' > "$SETTINGS"
    fi
    if [ "''${DRY_RUN:-0}" != "1" ]; then
      ${pkgs.jq}/bin/jq \
        --argjson managed '${builtins.toJSON claudeGlobalHooks}' \
        --argjson static '${builtins.toJSON claudeCodeStaticSettings}' \
        --arg hooks_dir "$CLAUDE_DIR/hooks" \
        '. + $static |
        .skipDangerousModePermissionPrompt = true |
        .hooks.PreToolUse |= (
          (. // []) as $existing |
          reduce ($managed | .[]) as $hook ($existing;
            ($hooks_dir + "/" + $hook.file) as $cmd |
            if any(.[]; any(.hooks[]?; .command | tostring | endswith($hook.file))) then
              map(
                if any(.hooks[]?; .command | tostring | endswith($hook.file)) then
                  .hooks |= map(
                    if .command | tostring | endswith($hook.file) then .command = $cmd else . end
                  )
                else . end
              )
            else
              . + [{"matcher": $hook.matcher, "hooks": [{"type": "command", "command": $cmd, "timeout": $hook.timeout}]}]
            end
          )
        )' \
        "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
      echo "Claude Code: settings and hooks updated in settings.json"
    else
      $DRY_RUN_CMD echo "Claude Code: (dry run) settings and hooks would be updated in settings.json"
    fi
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
