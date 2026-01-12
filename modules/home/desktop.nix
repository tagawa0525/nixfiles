# =============================================================================
# デスクトップ環境の設定
# =============================================================================
# COSMIC DE, XDG, fcitx5, mimeApps などデスクトップ関連の設定
# =============================================================================
{ pkgs, ... }:

{
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
  # COSMIC DE設定
  # ===========================================================================
  # System76製デスクトップ環境の設定ファイルを直接配置

  # ターミナルショートカットをAlacritty + tmuxに設定
  xdg.configFile."cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions".text = ''
    {
        Terminal: "alacritty -e local-tmux",
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
  # tmux接続用スクリプト
  # ===========================================================================
  home.packages = [
    # ローカルtmux起動（グループセッションで新規windowを作成）
    # 既存セッションがあれば新規windowを作成してそこに接続
    # なければ新規セッション作成
    (pkgs.writeShellScriptBin "local-tmux" ''
      if tmux has-session -t main 2>/dev/null; then
        tmux new-session -t main \; new-window
      else
        tmux new-session -s main
      fi
    '')
    # Tailscale経由でリモートホストにSSH接続し、tmuxセッションにアタッチ
    # 既存セッションがあれば新規windowを作成してそこに接続
    (pkgs.writeShellScriptBin "ssh-r995-tmux" ''
      ssh -t r995 'if tmux has-session -t main 2>/dev/null; then tmux new-session -t main \; new-window; else tmux new-session -s main; fi'
    '')
    (pkgs.writeShellScriptBin "ssh-xc8-tmux" ''
      ssh -t xc8 'if tmux has-session -t main 2>/dev/null; then tmux new-session -t main \; new-window; else tmux new-session -s main; fi'
    '')
  ];

  # ===========================================================================
  # tmux接続用ランチャーエントリ
  # ===========================================================================
  xdg.desktopEntries = {
    # ローカルtmux起動
    local-tmux = {
      name = "Terminal (tmux)";
      comment = "Alacrittyでtmuxセッションを起動";
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e local-tmux";
      terminal = false;
      categories = [ "System" "TerminalEmulator" ];
    };
    # r995（デスクトップ）へのtmux接続
    ssh-r995 = {
      name = "SSH to r995 (tmux)";
      comment = "Tailscale経由でr995にSSH接続しtmuxにアタッチ";
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e ssh-r995-tmux";
      terminal = false;
      categories = [ "Network" "RemoteAccess" ];
    };
    # xc8（ノートPC）へのtmux接続
    ssh-xc8 = {
      name = "SSH to xc8 (tmux)";
      comment = "Tailscale経由でxc8にSSH接続しtmuxにアタッチ";
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e ssh-xc8-tmux";
      terminal = false;
      categories = [ "Network" "RemoteAccess" ];
    };
  };
}
