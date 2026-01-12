# =============================================================================
# r995 ハードウェア設定（テンプレート）
# =============================================================================
# 注意: このファイルはテンプレートです。
# 実際のインストール時に以下のコマンドで生成された内容に置き換えてください：
#   sudo nixos-generate-config --show-hardware-config
#
# =============================================================================
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # ===========================================================================
  # カーネルモジュール
  # ===========================================================================
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ]; # AMD CPUのKVM仮想化サポート
  boot.extraModulePackages = [ ];

  # ===========================================================================
  # ファイルシステム（Btrfsサブボリューム構成）
  # ===========================================================================
  # 以下のサブボリュームを作成してください：
  #   sudo mkfs.btrfs -L nixos /dev/nvme0n1p2
  #   sudo mount /dev/nvme0n1p2 /mnt
  #   sudo btrfs subvolume create /mnt/@root
  #   sudo btrfs subvolume create /mnt/@home
  #   sudo btrfs subvolume create /mnt/@nix
  #   sudo btrfs subvolume create /mnt/@log
  #   sudo umount /mnt

  # TODO: 以下のUUIDを実際のディスクのUUIDに置き換えてください
  # 確認方法: lsblk -f

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/62f2c635-bfb9-42a6-9d9c-296a93fdb7c0";
    fsType = "btrfs";
    options = [ "subvol=@root" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/62f2c635-bfb9-42a6-9d9c-296a93fdb7c0";
    fsType = "btrfs";
    options = [ "subvol=@home" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/62f2c635-bfb9-42a6-9d9c-296a93fdb7c0";
    fsType = "btrfs";
    options = [ "subvol=@nix" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/62f2c635-bfb9-42a6-9d9c-296a93fdb7c0";
    fsType = "btrfs";
    options = [ "subvol=@log" ];
  };

  # EFIシステムパーティション
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/D878-9B1C";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # スワップ（ハイバネートを使用する場合は設定）
  swapDevices = [
    { device = "/dev/disk/by-uuid/86b93a4e-8f47-4345-8771-cb61f33ede09"; }
  ];

  # ===========================================================================
  # ハードウェア設定
  # ===========================================================================
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # AMD CPUマイクロコード更新
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ファームウェア更新サポート
  hardware.enableRedistributableFirmware = true;
}
