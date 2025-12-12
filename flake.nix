{
  description = "A daemon that monitors network connectivity and manages systemd targets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs = inputs @ { crane, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } (
    { moduleWithSystem, ... }:
    {
      systems = [
        "i686-linux"
        "x86_64-linux"
        "aarch64-linux"
        "armv7l-linux"
      ];
      imports = [ flake-parts.flakeModules.easyOverlay ];
      perSystem = { config, system, lib, pkgs, ...}:
        let
          craneLib = crane.mkLib pkgs;
          src = let
            unfilteredRoot = ./.;
          in lib.fileset.toSource {
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
            nativeBuildInputs = [ pkgs.pkg-config  pkgs.m4 ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          systemd-network-manager = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;
            postInstall = ''
              make install-units PREFIX="$out" LIBEXECDIR="$out/bin" DESTDIR=""
            '';
          });
        in rec {
          packages = {
            inherit systemd-network-manager;
            default = packages.systemd-network-manager;
          };
          overlayAttrs = {
            inherit (config.packages) systemd-network-manager;
          };
        };
      flake.nixosModules.default = moduleWithSystem (
        perSystem@{pkgs, self', ... }:
        nixos@{lib, config, ... }:
        let
          cfg = config.services.systemd-network-manager;
        in
        {
          options.services.systemd-network-manager = {
            enable = lib.mkEnableOption "enable the float homepage service";
            package = lib.mkPackageOption self'.packages "systemd-network-manager" { };
          };
          config = lib.mkIf cfg.enable {
            systemd = {
              packages = [ cfg.package ];
              services.systemd-network-manager.wantedBy = [ "systemd-networkd.service" ];
            };
            environment.systemPackages = [ cfg.package ];
          };
        });
    });
  }
