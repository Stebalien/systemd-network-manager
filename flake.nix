{
  description = "A daemon that monitors network connectivity and manages systemd targets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    inputs@{ nixpkgs, crane, ... }:
    let
      eachSystem = nixpkgs.lib.genAttrs [
        "i686-linux"
        "x86_64-linux"
        "aarch64-linux"
        "armv7l-linux"
      ];
      mkPackages =
        pkgs:
        let
          lib = pkgs.lib;
          craneLib = crane.mkLib pkgs;
          unfilteredRoot = ./.;
          src = lib.fileset.toSource {
            root = unfilteredRoot;
            fileset = lib.fileset.unions [
              (craneLib.fileset.commonCargoSources unfilteredRoot)
              ./Makefile
              ./units
            ];
          };
          commonArgs = {
            inherit src;
            strictDeps = true;
            buildInputs = [ pkgs.openssl ];
            nativeBuildInputs = [
              pkgs.pkg-config
              pkgs.m4
            ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          systemd-network-manager = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              postInstall = ''
                make install-units PREFIX="$out" LIBEXECDIR="$out/bin" DESTDIR=""
              '';
            }
          );
        in
        rec {
          inherit systemd-network-manager;
          default = systemd-network-manager;
        };
    in
    {
      packages = eachSystem (system: mkPackages nixpkgs.legacyPackages.${system});
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
      overlays.default = final: prev: {
        inherit (mkPackages final) systemd-network-manager;
      };

      nixosModules.default =
        {
          lib,
          config,
          pkgs,
          ...
        }:
        let
          cfg = config.services.systemd-network-manager;
        in
        {
          options.services.systemd-network-manager = {
            enable = lib.mkEnableOption "enable the systemd-network-manager";
            package = lib.mkPackageOption (mkPackages pkgs) "systemd-network-manager" { };
          };
          config = lib.mkIf cfg.enable {
            systemd = {
              packages = [ cfg.package ];
              services.systemd-network-manager.wantedBy = [ "systemd-networkd.service" ];
              user.services.systemd-network-manager.wantedBy = [ "default.target" ];
            };
          };
        };
    };
}
