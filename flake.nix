{
  description = "Deploy AtoM on NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
        ] f;
      nixpkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
          # For easier testing
          config.allowUnfree = true;
        }
      );
    in
    {

      overlays.default = final: prev: {
        accesstomemory = prev.callPackage ./pkgs/accesstomemory/package.nix { };
        gearmand = prev.callPackage ./pkgs/gearmand/package.nix { };
        elasticsearch711 = prev.callPackage ./pkgs/elasticsearch7/package.nix {
          elk7Version = "7.11.1";
          # util-linux = prev.util-linuxMinimal;
          # jre_headless = prev.jre8_headless;
          # enableUnfree = false;
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.accesstomemory;
          atom = self.packages.${system}.default;
          atom-dev = pkgs.callPackage ./pkgs/accesstomemory/package.nix { composerNoDev = false; };
          gearmand = pkgs.gearmand;
          elasticsearch711 = pkgs.elasticsearch711;
        }
      );

      nixosModules = {
        accesstomemory = import ./modules/accesstomemory.nix;
        gearmand = import ./modules/gearmand.nix;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          nixosTest =
            let
              modules = with self.nixosModules; [
                accesstomemory
                gearmand
              ];
              certs = import "${nixpkgs}/nixos/tests/common/acme/server/snakeoil-certs.nix";
              test = import ./tests/accesstomemory.nix { inherit pkgs modules certs; };
            in
            pkgs.testers.nixosTest test;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ node2nix ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgsFor.${system}.nixfmt-rfc-style);

    };
}
