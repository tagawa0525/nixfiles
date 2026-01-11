# Home Manager configuration for tagawa
{ config, pkgs, lib, niriOutputConfig ? "", ... }:

{
  imports = [
    ./niri.nix
  ];

  # Pass niriOutputConfig to niri.nix
  _module.args.niriOutputConfig = niriOutputConfig;

  home.stateVersion = "25.11";

  # Activation scripts
  home.activation.rustup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.rustup/toolchains" ]; then
      ${pkgs.rustup}/bin/rustup default stable
    fi
  '';

  home.activation.npmGlobalDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.npm-global"
    ${pkgs.nodejs}/bin/npm config set prefix "$HOME/.npm-global"
  '';

  home.activation.claudeCode = lib.hm.dag.entryAfter [ "npmGlobalDir" ] ''
    if ! command -v claude &> /dev/null; then
      ${pkgs.nodejs}/bin/npm install -g @anthropic-ai/claude-code
    fi
  '';

  # PATH
  home.sessionPath = [ "$HOME/.npm-global/bin" ];

  # Packages
  home.packages = with pkgs; [
    fastfetch
  ];

  # XDG directories
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

  # fcitx5 configuration
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

  # Fish shell
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting
    '';
    shellAliases = {
      ls = "eza";
      ll = "eza -la";
      la = "eza -a";
      lt = "eza --tree";
      cat = "bat";
      rebuild = "sudo nixos-rebuild switch --flake ~/NixOS#xc8";
      update = "cd ~/NixOS && nix flake update && sudo nixos-rebuild switch --flake .#xc8";
    };
  };

  # Git
  programs.git = {
    enable = true;
    settings = {
      user.name = "Hiroaki Tagawa";
      user.email = "tagawa0525@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # VSCode
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      github.copilot-chat
      mhutchie.git-graph
      ms-ceintl.vscode-language-pack-ja
      rust-lang.rust-analyzer
      vscodevim.vim
    ];
  };

  # Alacritty
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 12;
        normal.family = "Noto Sans Mono CJK JP";
      };
    };
  };

  # Neovim
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}
