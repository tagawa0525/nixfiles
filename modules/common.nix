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
    noto-fonts-emoji
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

  # User account
  users.users.tagawa = {
    isNormalUser = true;
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    extraGroups = [ "wheel" "podman" ];
    hashedPassword = "$6$g8T1ZyjV8uoBKzcp$HPjF9mnYkkpEyY3NXeK1HXv.Y3vcUSN4bHkzktlzuSi9SHxBYcNbbhtfwYHMSw5gQ2spy8fF9MORT.oUOUboA.";
    shell = pkgs.fish;
  };

  # Programs
  programs.firefox.enable = true;
  programs.fish.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    google-chrome
    neovim
    neovide
    nodejs
    alacritty

    # CLI tools
    ripgrep
    fd
    fzf
    eza
    bat
    jq
    lazygit
    tmux

    # Development
    git
    gh
    vscode
    clang
    rustup
    mise
    uv

    # System
    htop
    btop
    unzip
    wl-clipboard
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
