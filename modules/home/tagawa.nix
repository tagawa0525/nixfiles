# =============================================================================
# tagawa用のHome Manager設定
# =============================================================================
# ユーザー固有の設定（ドットファイル、シェル設定、アプリ設定など）を定義
# システム設定（common.nix）とは別に、ユーザー空間の設定を管理
# =============================================================================
{ config, pkgs, lib, niriOutputConfig ? "", ... }:

{
  imports = [
    ./niri.nix  # Niriウィンドウマネージャの設定
  ];

  # niriOutputConfigをniri.nixに渡す（ホスト固有のディスプレイ設定用）
  _module.args.niriOutputConfig = niriOutputConfig;

  # Home Managerのバージョン（変更しない）
  home.stateVersion = "25.11";

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
  # ユーザーパッケージ
  # ===========================================================================
  home.packages = with pkgs; [
    fastfetch  # システム情報表示（neofetchの高速版）
  ];

  # ===========================================================================
  # XDGユーザーディレクトリ
  # ===========================================================================
  # デスクトップ、ダウンロード等の標準ディレクトリを自動作成
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "$HOME/Desktop";
    download = "$HOME/Downloads";
    templates = "$HOME/Templates";
    publicShare = "$HOME/Public";
    documents = "$HOME/Documents";
    music = "$HOME/Music";
    pictures = "$HOME/Pictures";
    videos = "$HOME/Videos";
  };

  # ===========================================================================
  # fcitx5設定（日本語入力）
  # ===========================================================================
  # 入力メソッドのプロファイル設定
  # USキーボード + Mozcの構成
  xdg.configFile."fcitx5/profile".text = ''
    [Groups/0]
    Name=デフォルト
    Default Layout=us
    DefaultIM=mozc

    [Groups/0/Items/0]
    Name=keyboard-us
    Layout=

    [Groups/0/Items/1]
    Name=mozc
    Layout=

    [GroupOrder]
    0=デフォルト
  '';

  # fcitx5のホットキー設定
  xdg.configFile."fcitx5/config".text = ''
    [Hotkey]
    EnumerateWithTriggerKeys=True

    [Hotkey/TriggerKeys]
    0=Control+space

    [Hotkey/ActivateKeys]
    0=Alt+Alt_R

    [Hotkey/DeactivateKeys]
    0=Alt+Alt_L

    [Behavior]
    ShareInputState=All
    PreeditEnabledByDefault=True
    ShowInputMethodInformation=True
  '';

  # ===========================================================================
  # Zedエディタ設定
  # ===========================================================================
  # Rust製の高速エディタ。VSCodeライクなUIでVimモードをサポート
  xdg.configFile."zed/settings.json".text = ''
    {
      "terminal": {
        "font_weight": 400.0,
        "font_size": 16.0
      },
      "buffer_font_weight": 500.0,
      "ui_font_weight": 500.0,
      "buffer_font_family": ".ZedMono",
      "icon_theme": {
        "mode": "dark",
        "light": "Zed (Default)",
        "dark": "Zed (Default)"
      },
      "base_keymap": "VSCode",
      "vim_mode": true,
      "ui_font_size": 20.0,
      "buffer_font_size": 14.0,
      "theme": {
        "mode": "dark",
        "light": "One Light",
        "dark": "Ayu Dark"
      }
    }
  '';

  # ===========================================================================
  # デフォルトアプリケーション
  # ===========================================================================
  # ファイルタイプごとに使用するアプリケーションを指定
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # ターミナル
      "application/x-terminal-emulator" = "Alacritty.desktop";
      "x-scheme-handler/terminal" = "Alacritty.desktop";
      # ブラウザ（HTTPリンク、HTMLファイル）
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
      # テキストファイル
      "text/plain" = "neovide.desktop";
    };
  };

  # ===========================================================================
  # COSMIC DE設定
  # ===========================================================================
  # System76製デスクトップ環境の設定ファイルを直接配置

  # ターミナルショートカットをAlacrittyに設定
  xdg.configFile."cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions".text = ''
    {
        Terminal: "alacritty",
    }
  '';

  # 自動タイリング有効化（ウィンドウを自動的にタイル状に配置）
  xdg.configFile."cosmic/com.system76.CosmicComp/v1/autotile".text = "true";
  # ワークスペースごとにタイリング状態を管理
  xdg.configFile."cosmic/com.system76.CosmicComp/v1/autotile_behavior".text = "PerWorkspace";
  # ワークスペースの動作設定
  xdg.configFile."cosmic/com.system76.CosmicComp/v1/workspaces".text = ''
    (
        workspace_mode: OutputBound,
        workspace_layout: Vertical,
    )
  '';

  # ===========================================================================
  # Fishシェル
  # ===========================================================================
  # モダンなシェル。強力な補完、シンタックスハイライト、履歴検索
  programs.fish = {
    enable = true;
    # 起動時のグリーティングメッセージを無効化
    interactiveShellInit = ''
      set -g fish_greeting
    '';
    # よく使うコマンドのエイリアス
    shellAliases = {
      ls = "eza";           # モダンなls
      ll = "eza -la";       # 詳細表示
      la = "eza -a";        # 隠しファイル含む
      lt = "eza --tree";    # ツリー表示
      cat = "bat";          # シンタックスハイライト付きcat
      # NixOS再構築用エイリアス（ホスト名を動的に取得）
      rebuild = "sudo nixos-rebuild switch --flake ~/NixOS#$(hostname)";
      update = "cd ~/NixOS && nix flake update && sudo nixos-rebuild switch --flake .#$(hostname)";
    };
  };

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

  # ===========================================================================
  # VSCode設定
  # ===========================================================================
  # Home Managerで拡張機能を宣言的に管理
  programs.vscode = {
    enable = true;
    profiles.default = {
        extensions = with pkgs.vscode-extensions; [
        github.copilot-chat           # AIペアプログラミング
        mhutchie.git-graph            # Gitの履歴をグラフ表示
        ms-ceintl.vscode-language-pack-ja  # 日本語UI
        rust-lang.rust-analyzer       # Rust言語サポート
        vscodevim.vim                 # Vimキーバインド
      ];
      userSettings = {
        # VS Code Speechの音声認識言語を日本語に設定
        "github.copilot.nextEditSuggestions.enabled" = true;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;
        "window.customMenuBarAltFocus" = false; # Alキー単押しでMenu Barにフォーカスしない
        "git.autofetch" = true;
        "accessibility.voice.speechLanguage" = "ja-JP"; # 音声認識で使用する言語
	"remote.SSH.useExecServer" = false;
      };
    };
  };

  # ===========================================================================
  # Alacritty設定（ターミナル）
  # ===========================================================================
  # Rust製GPU加速ターミナル。軽量で高速
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 12;
        normal.family = "Noto Sans Mono CJK JP";  # 日本語対応等幅フォント
      };
    };
  };

  # ===========================================================================
  # Neovim設定
  # ===========================================================================
  programs.neovim = {
    enable = true;
    defaultEditor = true;  # $EDITORに設定
    viAlias = true;        # viコマンドでneovimを起動
    vimAlias = true;       # vimコマンドでneovimを起動
  };

  # ===========================================================================
  # Direnv（ディレクトリごとの環境変数）
  # ===========================================================================
  # .envrcファイルでディレクトリ進入時に自動で環境をロード
  # nix-direnv: flake.nixを使った開発環境の自動切り替え
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;  # use flake で nix develop 環境を自動ロード
  };

  # ===========================================================================
  # Starshipプロンプト
  # ===========================================================================
  # Rust製の高速でカスタマイズ可能なプロンプト
  # Git状態、言語バージョン、実行時間などを表示
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  # ===========================================================================
  # Zoxide（スマートcd）
  # ===========================================================================
  # 移動履歴を学習し、部分一致でディレクトリにジャンプ
  # 例: z proj → ~/projects/myproject に移動
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # ===========================================================================
  # VS Code Server（リモート接続用）
  # ===========================================================================
  # NixOSでVS Code Remote SSHを動作させるためのサービス
  # ダウンロードされたサーバーバイナリを自動でパッチする
  services.vscode-server.enable = true;
}
