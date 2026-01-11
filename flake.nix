{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      # Don't follow nixpkgs to avoid Rust version incompatibility
    };
  };

  outputs = { self, nixpkgs, home-manager, lanzaboote, ... }: {
    nixosConfigurations = {
      # Laptop
      xc8 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/xc8
          ./modules/common.nix
          lanzaboote.nixosModules.lanzaboote
          home-manager.nixosModules.home-manager
          {
            nixpkgs.overlays = [ (import ./overlays/vscode.nix) ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = import ./hosts/xc8/niri-output.nix;
            home-manager.users.tagawa = import ./modules/home/tagawa.nix;
          }
        ];
      };

      # Desktop
      # r995 = nixpkgs.lib.nixosSystem {
      #   system = "x86_64-linux";
      #   modules = [
      #     ./hosts/r995
      #     ./modules/common.nix
      #     home-manager.nixosModules.home-manager
      #     {
      #       home-manager.useGlobalPkgs = true;
      #       home-manager.useUserPackages = true;
      #       home-manager.backupFileExtension = "backup";
      #       home-manager.users.tagawa = import ./modules/home/tagawa.nix;
      #     }
      #   ];
      # };
    };
  };
}
