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
        }
      );
    in
    {

      overlays.default = final: prev: {
        accesstomemory = prev.callPackage ./pkgs/accesstomemory/package.nix { };
        gearmand = prev.callPackage ./pkgs/gearmand/package.nix { };
        elasticsearch6 = prev.callPackage ./pkgs/elasticsearch6/package.nix {
          elk6Version = "6.8.23";
          util-linux = prev.util-linuxMinimal;
          jre_headless = prev.jre8_headless;
          # enableUnfree = false;
        };
        lessc = (prev.callPackage ./pkgs/lessc3 { })."less-3.13.1";
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.accesstomemory;
          atom = self.packages.${system}.default;
          gearmand = pkgs.gearmand;
          elasticsearch6 = pkgs.elasticsearch6;
          lessc = pkgs.lessc;
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
            pkgs.nixosTest test;
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
