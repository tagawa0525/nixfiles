# Common system configuration shared across all hosts
{ config, lib, pkgs, ... }:

{
  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Network
  networking.networkmanager.enable = true;

  # Timezone and locale
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.supportedLocales = [
    "ja_JP.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    font-awesome
  ];
  fonts.fontconfig = {
    defaultFonts = {
      sansSerif = [ "Noto Sans CJK JP" "Noto Sans" ];
      serif = [ "Noto Serif CJK JP" "Noto Serif" ];
      monospace = [ "Noto Sans Mono CJK JP" "Noto Sans Mono" ];
    };
  };

  # Japanese input method
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };

  # Environment variables
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    PATH = [ "$HOME/.npm-global/bin" ];
  };

  # Desktop environment
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  # Podman
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  security.unprivilegedUsernsClone = true;

  # libvirt/KVM
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # User account
  users.users.tagawa = {
    isNormalUser = true;
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    extraGroups = [ "wheel" "podman" "libvirtd" ];
    hashedPassword = "$6$g8T1ZyjV8uoBKzcp$HPjF9mnYkkpEyY3NXeK1HXv.Y3vcUSN4bHkzktlzuSi9SHxBYcNbbhtfwYHMSw5gQ2spy8fF9MORT.oUOUboA.";
    shell = pkgs.fish;
  };

  # Programs
  programs.firefox.enable = true;
  programs.fish.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    # ─────────────────────────────────────────────────────────────
    # Browsers
    # ─────────────────────────────────────────────────────────────
    google-chrome  # Chromiumベースのウェブブラウザ

    # ─────────────────────────────────────────────────────────────
    # Editors & Terminal
    # ─────────────────────────────────────────────────────────────
    neovim    # モダンなVimフォーク
    neovide   # Neovim用のGUIフロントエンド
    vscode    # 拡張機能豊富なコードエディタ
    alacritty # GPU加速ターミナルエミュレータ

    # ─────────────────────────────────────────────────────────────
    # Languages & Runtimes
    # ─────────────────────────────────────────────────────────────
    nodejs  # JavaScript/TypeScriptランタイム(Claude Code Install用)
    clang   # C/C++コンパイラ (LLVMベース)
    rustup  # Rustツールチェーン管理
    mise    # 多言語バージョン管理 (asdf代替)
    uv      # 高速Pythonパッケージマネージャ

    # ─────────────────────────────────────────────────────────────
    # Version Control
    # ─────────────────────────────────────────────────────────────
    git     # 分散バージョン管理システム
    gh      # GitHub CLI
    lazygit # Git用のターミナルUI
    delta   # git diff/grep用のシンタックスハイライト

    # ─────────────────────────────────────────────────────────────
    # CLI Utilities - Search & Navigation
    # ─────────────────────────────────────────────────────────────
    ripgrep # 高速grep (rg)
    fd      # 高速find
    fzf     # ファジーファインダー
    zoxide  # スマートcd (頻繁に使うディレクトリを学習)

    # ─────────────────────────────────────────────────────────────
    # CLI Utilities - File & Text
    # ─────────────────────────────────────────────────────────────
    eza   # モダンなls代替
    bat   # シンタックスハイライト付きcat
    jq    # JSONプロセッサ
    unzip # ZIPアーカイブ展開
    tmux  # ターミナルマルチプレクサ

    # ─────────────────────────────────────────────────────────────
    # Debug & Analysis
    # ─────────────────────────────────────────────────────────────
    strace    # システムコールトレーサ
    ltrace    # ライブラリコールトレーサ
    tokei     # コード行数カウント
    hyperfine # コマンドベンチマーク
    dust      # ディスク使用量の可視化 (du代替)

    # ─────────────────────────────────────────────────────────────
    # System Monitoring
    # ─────────────────────────────────────────────────────────────
    htop # インタラクティブなプロセスビューア
    btop # リソースモニタ (htop代替)

    # ─────────────────────────────────────────────────────────────
    # GUI Tools - Development
    # ─────────────────────────────────────────────────────────────
    podman-desktop # コンテナ管理GUI
    meld           # ビジュアルdiff/マージツール
    dbeaver-bin    # データベースGUIクライアント

    # ─────────────────────────────────────────────────────────────
    # System Utilities
    # ─────────────────────────────────────────────────────────────
    wl-clipboard # Wayland用クリップボードユーティリティ
    sbctl        # Secure Boot鍵管理
  ];


  # GNOME Keyring (for password/secret management)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
    ports = [ 22 ];
  };

  # Tailscale
  services.tailscale.enable = true;

  # Keyboard remapping (works on Wayland/X11/TTY)
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = ["*"];
      settings.main = {
        capslock = "overload(control, esc)";  # 単独でEsc、組み合わせでCtrl
        # capslock = "leftcontrol";
      };
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 22 ];

  # XDG user directories defaults
  environment.etc."xdg/user-dirs.defaults".text = ''
    DESKTOP=Desktop
    DOWNLOAD=Downloads
    TEMPLATES=Templates
    PUBLICSHARE=Public
    DOCUMENTS=Documents
    MUSIC=Music
    PICTURES=Pictures
    VIDEOS=Videos
  '';
}
