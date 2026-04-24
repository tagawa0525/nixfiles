# =============================================================================
# エディタ関連の設定
# =============================================================================
# VSCode, Neovim, Zed, Alacritty などエディタ・ターミナルの設定
# =============================================================================
{ lib, pkgs, ... }:

let
  # パッケージから拡張機能IDを抽出
  getExtensionId = ext: "${ext.vscodeExtPublisher}.${ext.vscodeExtName}";

  # リモートにもインストールする拡張機能（ワークスペース拡張機能）
  workspaceExtensions = [
    # AI/コーディング支援
    # github.copilot-chat は VS Code 1.117+ 以降 builtin 化されているため明示インストール不要。
    # 明示インストールすると VS Code 側で skip され、かつ auto-update が extensions dir に
    # 書き込めず ENOENT を起こす。
    pkgs.vscode-marketplace.anthropic.claude-code # Claude Code CLI連携（diff view）

    # Git
    # gitlensはnixpkgs側が更新追従していないためmarketplace-releaseを使用
    pkgs.vscode-marketplace-release.eamodio.gitlens # Git機能強化（blame、履歴、比較）
    pkgs.vscode-extensions.mhutchie.git-graph # Gitの履歴をグラフ表示
    pkgs.vscode-extensions.github.vscode-github-actions # GitHub Actionsワークフロー編集

    # 言語サポート
    pkgs.vscode-extensions.jnoortheen.nix-ide # Nix
    # rust-analyzerもnixpkgs側が古いためmarketplace-releaseを使用
    pkgs.vscode-marketplace-release.rust-lang.rust-analyzer # Rust
    pkgs.vscode-extensions.ms-python.python # Python
    pkgs.vscode-extensions.ms-python.vscode-pylance # Python型チェック・補完
    pkgs.vscode-extensions.charliermarsh.ruff # Python フォーマット・lint
    pkgs.vscode-extensions.redhat.vscode-yaml # YAML
    pkgs.vscode-extensions.tamasfe.even-better-toml # TOML
    pkgs.vscode-extensions.davidanson.vscode-markdownlint # Markdownリンター

    # 開発環境
    pkgs.vscode-extensions.mkhl.direnv # direnv環境変数の自動読み込み

    # エディタ機能強化
    pkgs.vscode-extensions.vscodevim.vim # Vimキーバインド
    pkgs.vscode-extensions.usernamehw.errorlens # エラー・警告をインライン表示
    pkgs.vscode-extensions.gruntfuggly.todo-tree # TODO/FIXMEコメント一覧表示
    pkgs.vscode-extensions.fill-labs.dependi # 依存関係のバージョン管理
  ];

  # ローカルのみの拡張機能（UI拡張機能）
  localOnlyExtensions = [
    # UI/ローカライズ
    pkgs.vscode-extensions.ms-ceintl.vscode-language-pack-ja # 日本語UI

    # リモート開発
    pkgs.vscode-extensions.ms-vscode-remote.remote-ssh # リモートSSH接続
    pkgs.vscode-extensions.ms-vscode-remote.remote-containers # Dev Containers対応
    pkgs.vscode-extensions.ms-vscode.remote-explorer # リモート接続管理

    # 音声入力
    pkgs.vscode-extensions.ms-vscode.vscode-speech # 音声入力
    pkgs.vscode-marketplace-release.ms-vscode.vscode-speech-language-pack-ja-jp # 日本語言語パック
  ];
in
{
  # ===========================================================================
  # VSCode設定
  # ===========================================================================
  # VSCode拡張機能と設定（Home Manager経由、nix-vscode-extensionsを使用）
  programs.vscode = {
    enable = true;
    # package = pkgs.nur-vscode-latest.vscode-insiders; # Insiders版を使用してGitHub Copilot Chatを有効化
    package = pkgs.nur-vscode-latest.vscode; # Stable版を使用してGitHub Copilot Chatを有効化
    # VS Code 1.117+ の builtin copilot-chat は autoUpdate 設定に関わらず
    # 特別ルートで自動更新を試みる。extensions dir を完全read-onlyにすると
    # mkdir '.xxx' が ENOENT で失敗するため、書き込み可能にしている。
    # Nix 管理の各拡張は依然 /nix/store への symlink として配置される。
    mutableExtensionsDir = true;
    profiles.default = {
      extensions = workspaceExtensions ++ localOnlyExtensions ++ [
        # Rustデバッガー。nix-vscode-extensions 側は supportedVersion 固定の
        # assertion を持ち新バージョンで落ちるため、nixpkgs 本家版を使用する。
        pkgs.vscode-extensions.vadimcn.vscode-lldb
      ];
      userSettings = {
        "locale" = "ja"; # VS Codeの表示言語を日本語に設定
        "github.copilot.nextEditSuggestions.enabled" = true;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;
        "window.customMenuBarAltFocus" = false; # Alキー単押しでMenu Barにフォーカスしない
        "git.autofetch" = true;
        # VS Code Speechの音声認識言語を日本語に設定
        "accessibility.voice.speechLanguage" = "ja-JP"; # 音声認識で使用する言語
        "remote.SSH.useExecServer" = true;
        "remote.SSH.enableRemoteCommand" = true;
        "remote.SSH.enableDynamicForwarding" = false;
        "dev.containers.dockerPath" = "podman";
        "workbench.startupEditor" = "none";
        "editor.lineNumbers" = "relative"; # 相対行番号を表示
        # NixOSでは署名検証に必要なライブラリがないため無効化
        "extensions.verifySignature" = false;
        # Nix IDE設定
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd"; # nixdをLSPとして使用
        "chat.tools.terminal.outputLocation" = "chat";
        # Python設定（Ruff + Pylance）
        "[python]" = {
          "editor.defaultFormatter" = "charliermarsh.ruff";
          "editor.formatOnSave" = true;
          "editor.codeActionsOnSave" = {
            "source.fixAll" = "explicit"; # Ruffの自動修正
            "source.organizeImports" = "explicit"; # import整理
          };
        };
        # Markdown設定（markdownlint）
        "[markdown]" = {
          "editor.codeActionsOnSave" = {
            "source.fixAll.markdownlint" = "explicit";
          };
        };
        # markdownlint設定は ~/.markdownlintrc を参照（development.nixで管理）
        # Rust設定（rust-analyzer）
        "[rust]" = {
          "editor.defaultFormatter" = "rust-lang.rust-analyzer";
          "editor.formatOnSave" = true;
        };
        "rust-analyzer.check.command" = "clippy"; # 保存時にclippyでlint
        "rust-analyzer.inlayHints.parameterHints.enable" = true; # パラメータ名ヒント
        "rust-analyzer.inlayHints.typeHints.enable" = true; # 型ヒント
        "rust-analyzer.inlayHints.chainingHints.enable" = true; # メソッドチェーンの型ヒント
        "rust-analyzer.procMacro.enable" = true; # プロシージャルマクロサポート
        "rust-analyzer.cargo.features" = "all"; # 全featureを有効化
        # リモート接続時に自動インストールする拡張機能
        "remote.SSH.defaultExtensions" = map getExtensionId workspaceExtensions;
      };
    };
  };

  # Copilot Chat は VS Code 同梱の copilot 拡張 (/nix/store 配下、mode 444) から
  # copilotCLIShim.js / copilotDebugCommand.js 等を globalStorage にコピーする。
  # 初回コピーで読み取り専用権限が保持され、バージョン更新時の再コピーが
  # EACCES で失敗するため、activation 時に書き込み権限を付与しておく。
  home.activation.fixCopilotChatGlobalStoragePerms =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="$HOME/.config/Code/User/globalStorage/github.copilot-chat"
      if [ -d "$target" ]; then
        chmod -R u+w "$target" || true
      fi
    '';

  # ===========================================================================
  # Neovim設定
  # ===========================================================================
  programs.neovim = {
    enable = true;
    defaultEditor = true; # $EDITORに設定
    viAlias = true; # viコマンドでneovimを起動
    vimAlias = true; # vimコマンドでneovimを起動
    extraConfig = ''
      set number         " 行番号を表示
      set relativenumber " 相対行番号を表示
    '';
  };

  # ===========================================================================
  # Zedエディタ設定
  # ===========================================================================
  # Rust製の高速エディタ。VSCodeライクなUIでVimモードをサポート
  home.packages = with pkgs; [
    zed-editor
  ];

  xdg.configFile."zed/settings.json".text = builtins.toJSON {
    terminal = {
      font_weight = 400.0;
      font_size = 16.0;
    };
    buffer_font_weight = 500.0;
    ui_font_weight = 500.0;
    buffer_font_family = ".ZedMono";
    icon_theme = {
      mode = "dark";
      light = "Zed (Default)";
      dark = "Zed (Default)";
    };
    base_keymap = "VSCode";
    vim_mode = true;
    relative_line_numbers = true;
    ui_font_size = 20.0;
    buffer_font_size = 14.0;
    theme = {
      mode = "dark";
      light = "One Light";
      dark = "Ayu Dark";
    };
  };

  # ===========================================================================
  # Alacritty設定（ターミナル）
  # ===========================================================================
  # Rust製GPU加速ターミナル。軽量で高速
  programs.alacritty = {
    enable = true;
    settings = {
      window.decorations = "None"; # タイトルバーを非表示
      font = {
        size = 12;
        normal.family = "Noto Sans Mono CJK JP"; # 日本語対応等幅フォント
      };
    };
  };
}
