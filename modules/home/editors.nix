# =============================================================================
# エディタ関連の設定
# =============================================================================
# VSCode, Neovim, Zed, Alacritty などエディタ・ターミナルの設定
# =============================================================================
{ pkgs, ... }:

{
  # ===========================================================================
  # VSCode設定
  # ===========================================================================
  # VSCode拡張機能と設定（Home Manager経由、nur-tagawa.vscodeを使用）
  programs.vscode = {
    enable = true;
    package = pkgs.nur-tagawa.vscode;
    mutableExtensionsDir = false; # 拡張機能ディレクトリをNixで完全管理
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        github.copilot-chat # AIペアプログラミング
        github.vscode-github-actions
        fill-labs.dependi
        jnoortheen.nix-ide # Nix言語サポート（シンタックスハイライト、補完、フォーマット）
        mhutchie.git-graph # Gitの履歴をグラフ表示
        ms-ceintl.vscode-language-pack-ja # 日本語UI
        ms-vscode-remote.vscode-remote-extensionpack
        ms-vscode-remote.remote-containers
        ms-vscode.vscode-speech
        rust-lang.rust-analyzer # Rust言語サポート
        vscodevim.vim # Vimキーバインド
        # nur-tagawa提供のカスタム拡張機能（GitHub Actionsで自動更新）
        vscode-speech-language-pack-ja-jp # VS Code Speech 日本語言語パック
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
      };
    };
  };

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
