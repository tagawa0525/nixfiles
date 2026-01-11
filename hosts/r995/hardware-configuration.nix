# =============================================================================
# r995 ハードウェア設定（テンプレート）
# =============================================================================
# 注意: このファイルはテンプレートです。
# 実際のインストール時に以下のコマンドで生成された内容に置き換えてください：
#   sudo nixos-generate-config --show-hardware-config
#
# 特に以下のUUIDは実際のディスクに合わせて変更が必要：
#   - /dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
# =============================================================================
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # ===========================================================================
  # カーネルモジュール
  # ===========================================================================
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];  # AMD CPUのKVM仮想化サポート
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

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "btrfs";
      options = [ "subvol=@root" "compress=zstd" "noatime" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "btrfs";
      options = [ "subvol=@home" "compress=zstd" "noatime" ];
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "btrfs";
      options = [ "subvol=@nix" "compress=zstd" "noatime" ];
    };

  fileSystems."/var/log" =
    { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "btrfs";
      options = [ "subvol=@log" "compress=zstd" "noatime" ];
    };

  # EFIシステムパーティション
  # TODO: UUIDを実際のESPパーティションのUUIDに置き換えてください
  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/XXXX-XXXX";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  # スワップ（ハイバネートを使用する場合は設定）
  # swapDevices =
  #   [ { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; }
  #   ];

  # ===========================================================================
  # ハードウェア設定
  # ===========================================================================
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # AMD CPUマイクロコード更新
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ファームウェア更新サポート
  hardware.enableRedistributableFirmware = true;
}
