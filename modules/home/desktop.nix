# =============================================================================
# デスクトップ環境の設定
# =============================================================================
# COSMIC DE, XDG, fcitx5, mimeApps などデスクトップ関連の設定
# =============================================================================

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
  # GNOME Keyring（パスワード・認証情報管理）
  # ===========================================================================
  # VSCode、Git、SSH等の認証情報を安全に保存
  # libsecretを使用してアプリケーションから暗号化されたストレージにアクセス可能
  services.gnome-keyring = {
    enable = true;
    components = [
      "pkcs11" # 証明書・鍵の管理
      "secrets" # パスワード・シークレットの管理（VSCodeが使用）
      "ssh" # SSH鍵の管理
    ];
  };

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

}
