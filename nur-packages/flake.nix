{
  description = "tagawa's NUR packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        import ./default.nix {
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        }
      );
    };
}
