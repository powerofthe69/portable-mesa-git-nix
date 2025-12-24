{
  pkgs,
  mesa-src,
  libdrm-src,
  wayland-protocols-src,
}:

let
  lib = pkgs.lib;

  # Get short commit hash for versioning
  mesaVersion = builtins.substring 0 7 (mesa-src.rev or "unknown");
  libdrmVersion = builtins.substring 0 7 (libdrm-src.rev or "unknown");
  waylandProtocolsVersion = builtins.substring 0 7 (wayland-protocols-src.rev or "unknown");

  # Build libdrm-git
  libdrm-git = pkgs.libdrm.overrideAttrs (old: {
    pname = "libdrm-git";
    version = "${libdrmVersion}";
    src = libdrm-src;
  });

  # Build wayland-protocols-git
  wayland-protocols-git = pkgs.wayland-protocols.overrideAttrs (old: {
    pname = "wayland-protocols-git";
    version = "${waylandProtocolsVersion}";
    src = wayland-protocols-src;
  });

  # Common mesa configuration
  makeMesa =
    {
      is32bit ? false,
    }:
    let
      basePkgs = if is32bit then pkgs.pkgsi686Linux else pkgs;
    in
    basePkgs.mesa.overrideAttrs (old: {
      pname = "mesa-git";
      version = "${mesaVersion}";
      src = mesa-src;

      # Remove spirv2dxil output since we're not building DirectX stuff
      outputs = lib.remove "spirv2dxil" (old.outputs or [ "out" ]);

      buildInputs =
        old.buildInputs
        ++ [
          pkgs.libdisplay-info
        ]
        ++ (
          if is32bit then
            [ ]
          else
            [
              libdrm-git
            ]
        );

      nativeBuildInputs = old.nativeBuildInputs ++ [
        wayland-protocols-git
        pkgs.perl
      ];

      # Remove spirv2dxil from postInstall
      postInstall =
        builtins.replaceStrings
          [ "moveToOutput bin/spirv2dxil $spirv2dxil" "moveToOutput \"lib/libspirv_to_dxil*\" $spirv2dxil" ]
          [ "" "" ]
          (old.postInstall or "");

      mesonFlags =
        # Filter out flags we want to override from the original
        (builtins.filter (
          flag:
          !(lib.hasPrefix "-Dgallium-drivers=" flag)
          && !(lib.hasPrefix "-Dvulkan-drivers=" flag)
          && !(lib.hasPrefix "-Dvulkan-layers=" flag)
          && !(lib.hasPrefix "-Dgallium-rusticl=" flag)
          && !(lib.hasPrefix "-Dteflon=" flag)
        ) (old.mesonFlags or [ ]))
        ++ [
          "-Dplatforms=x11,wayland"
          "-Dgallium-drivers=${if is32bit then "radeonsi,zink,llvmpipe,iris" else "all"}"
          "-Dvulkan-drivers=amd,intel,nouveau${if is32bit then "" else ",swrast"}"
          "-Dvulkan-layers=anti-lag,device-select,overlay"
          "-Dteflon=true"
          "-Dgallium-extra-hud=true"
          "-Dvideo-codecs=all"
          "-Dinstall-mesa-clc=true"
          "-Dinstall-precomp-compiler=true"
          "-Dgallium-mediafoundation=disabled"
          "-Dandroid-libbacktrace=disabled"
          "-Dmicrosoft-clc=disabled"
          "-Dspirv-to-dxil=false"
        ]
        ++ (
          if is32bit then
            [
              "-Dgallium-rusticl=false"
            ]
          else
            [
              "-Dgallium-rusticl=true"
              "-Dgallium-rusticl-enable-drivers=auto"
              "-Dintel-rt=enabled"
            ]
        );

      # Remove patches that don't apply to git
      patches = builtins.filter (
        p:
        let
          name = baseNameOf (toString p);
        in
        !(lib.hasPrefix "gallivm-llvm-21" name)
      ) (old.patches or [ ]);

      # Inject git version to driver name
      postPatch = (old.postPatch or "") + ''
        BASE_VERSION=$(cat VERSION | tr -d '\n')
        NEW_VERSION="$BASE_VERSION (git-${mesaVersion})"
        echo "$NEW_VERSION" > VERSION
      '';
    });

  mesa-git = makeMesa { is32bit = false; };
  mesa32-git = makeMesa { is32bit = true; };

  # Bundle with dependencies for portability
  bundle =
    pkgs.runCommand "mesa-git-${mesaVersion}-bundle"
      {
        nativeBuildInputs = [ pkgs.patchelf ];
      }
      ''
            mkdir -p $out/{lib,lib32,share}
            mkdir -p $out/lib/bundled
            mkdir -p $out/lib32/bundled

            echo "Copying 64-bit Mesa..."
            cp -rL ${mesa-git}/lib/* $out/lib/ || true
            cp -rL ${mesa-git}/share/* $out/share/ || true

            echo "Copying 32-bit Mesa..."
            cp -rL ${mesa32-git}/lib/* $out/lib32/ || true

            echo "Bundling 64-bit dependencies..."
            for lib in \
              ${pkgs.llvmPackages.libllvm.lib}/lib/libLLVM*.so* \
              ${pkgs.libxml2.out}/lib/libxml2.so* \
              ${pkgs.icu}/lib/libicuuc.so* \
              ${pkgs.icu}/lib/libicudata.so*; do
              if [ -e "$lib" ]; then
                cp -Ln "$lib" $out/lib/bundled/ 2>/dev/null || true
              fi
            done

            echo "Bundling 32-bit dependencies..."
            for lib in \
              ${pkgs.pkgsi686Linux.llvmPackages.libllvm.lib}/lib/libLLVM*.so* \
              ${pkgs.pkgsi686Linux.libxml2.out}/lib/libxml2.so* \
              ${pkgs.pkgsi686Linux.icu}/lib/libicuuc.so* \
              ${pkgs.pkgsi686Linux.icu}/lib/libicudata.so*; do
              if [ -e "$lib" ]; then
                cp -Ln "$lib" $out/lib32/bundled/ 2>/dev/null || true
              fi
            done

            echo "Patching RPATH for 64-bit libraries..."
            for driver in $out/lib/libvulkan_*.so $out/lib/libGLX_mesa.so* $out/lib/libEGL_mesa.so* $out/lib/dri/*.so; do
              if [ -f "$driver" ]; then
                patchelf --set-rpath '$ORIGIN:$ORIGIN/bundled:$ORIGIN/../bundled' "$driver" 2>/dev/null || true
              fi
            done

            echo "Patching RPATH for 32-bit libraries..."
            for driver in $out/lib32/libvulkan_*.so $out/lib32/libGLX_mesa.so* $out/lib32/libEGL_mesa.so* $out/lib32/dri/*.so; do
              if [ -f "$driver" ]; then
                patchelf --set-rpath '$ORIGIN:$ORIGIN/bundled:$ORIGIN/../bundled' "$driver" 2>/dev/null || true
              fi
            done

            echo "Creating version info..."
            cat > $out/VERSION << EOF
        mesa: ${mesa-src.rev or "unknown"}
        libdrm: ${libdrm-src.rev or "unknown"}
        wayland-protocols: ${wayland-protocols-src.rev or "unknown"}
        EOF

            echo "Bundle complete!"
      '';

in
{
  inherit
    mesa-git
    mesa32-git
    libdrm-git
    wayland-protocols-git
    bundle
    mesaVersion
    ;
}
