{
  description = "A daemon that monitors network connectivity and manages systemd targets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    crate2nix = {
      url = "github:nix-community/crate2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
  };

  outputs = inputs @ { crate2nix, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86-linux"
      "x86_64-linux"
      "aarch64-linux"
    ];
    imports = [ flake-parts.flakeModules.easyOverlay ];
    perSystem = { config, system, pkgs, ...}:
      let
        cargoNix = crate2nix.tools.${system}.appliedCargoNix {
          name = "systemd-network-manager";
          src = ./.;
        };
      in rec {
        packages = {
          systemd-network-manager = cargoNix.rootCrate.build.overrideAttrs (prev: {
            nativeBuildInputs = (prev.nativeBuildInputs or []) ++ [ pkgs.m4 ];
            postInstall = prev.postInstall + ''
              make install-units PREFIX="$out" LIBEXECDIR="$out/bin" DESTDIR=""
            '';
          });
          default = packages.systemd-network-manager;
        };
        overlayAttrs = {
          inherit (config.packages) systemd-network-manager;
        };
      };
  };
}
