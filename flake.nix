{
  description = "Mesa-git built for deployment with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  nixConfig = {
    extra-substituters = [ "https://nix-cache.tokidoki.dev/mesa-git" ];
    extra-trusted-public-keys = [
      "mesa-git:QdQcgcLR80ALQIG0hR0YZaPbbdrBvHy7R+zwMjYWUyw="
    ];
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";

      sourceData = builtins.fromJSON (builtins.readFile ./pkgs/sources.json);

      fetchSrc =
        pkgs: key:
        let
          src = sourceData.${key};
        in
        pkgs.fetchgit { inherit (src) url rev sha256; } // { inherit (src) rev; };

      makeMesaPkgs =
        pkgs:
        import ./pkgs {
          inherit pkgs;
          mesa-src = fetchSrc pkgs "mesa";
          libdrm-src = fetchSrc pkgs "libdrm";
          wayland-protocols-src = fetchSrc pkgs "wayland-protocols";
        };

      # For flake outputs (packages, version info)
      pkgs = nixpkgs.legacyPackages.${system};
      mesaPkgs = makeMesaPkgs pkgs;
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

      # Overlay injects mesa-git into pkgs
      overlays.default =
        final: prev:
        let
          mesaPkgs = makeMesaPkgs final;
        in
        {
          inherit (mesaPkgs)
            mesa-git
            mesa32-git
            libdrm-git
            wayland-protocols-git
            ;
        };

      # NixOS module to replace system Mesa
      nixosModules.default = import ./modules/mesa-git.nix;
      nixosModules.mesa-git = self.nixosModules.default;

      # Metadata
      lib.version = sourceData.mesa.rev;
    };
}
