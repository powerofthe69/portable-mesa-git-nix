{
  description = "Mesa-git built for deployment with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      sourceData = builtins.fromJSON (builtins.readFile ./pkgs/sources.json);
      fetchSrc =
        key:
        let
          src = sourceData.${key};
          drv = pkgs.fetchgit {
            inherit (src) url rev sha256;
          };
        in
        drv // { rev = src.rev; };

      mesa-src = fetchSrc "mesa";
      libdrm-src = fetchSrc "libdrm";
      wayland-protocols-src = fetchSrc "wayland-protocols";

      mesaPkgs = import ./pkgs {
        inherit
          pkgs
          mesa-src
          libdrm-src
          wayland-protocols-src
          ;
      };

    in
    {
      packages.${system} = {
        inherit (mesaPkgs)
          mesa-git
          mesa32-git
          libdrm-git
          wayland-protocols-git
          bundle
          ;

        default = mesaPkgs.mesa-git;
      };

      # For easy version checking in CI
      version = mesaPkgs.mesaVersion;
      commit = mesa-src.rev or "unknown";
    };
}
