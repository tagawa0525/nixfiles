# Host-specific configuration for xc8
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot with Secure Boot (lanzaboote)
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
  boot.resumeDevice = "/dev/disk/by-label/swap";
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Host
  networking.hostName = "xc8";

  # This value determines the NixOS release
  system.stateVersion = "25.11";
}
