{
  self,
  lib,
  stdenv,
  deno,
  python3,
  python3Packages,
  rsync,
  runCommandLocal,
  zip,
}:

let
  manifestFile =
    runCommandLocal "vimium-manifest.json"
      {
        nativeBuildInputs = [
          python3
          python3Packages.json5
        ];
        src = self;
      }
      ''
        python3 - <<EOF
        import json
        import json5
        with open("$src/manifest.json5") as f:
          manifest = json5.load(f)
        with open("$out", "w") as f:
          json.dump(manifest, f)
        EOF
      '';
  manifest = lib.importJSON manifestFile;

  # Prefetch Deno dependencies into a cache directory.
  denoDeps = stdenv.mkDerivation {
    name = "vimium-deno-deps";
    src = self;
    nativeBuildInputs = [ deno ];
    dontUnpack = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-lFaC1GsB9T4Gfkzg8H8SBkN5VBGLqp1aWAK3rnYuXOo=";

    buildPhase = ''
      mkdir -p "$TMPDIR/source/nix"
      cp "$src/nix/." "$TMPDIR/source/nix"
      cd "$TMPDIR/source"
      export DENO_DIR="$out"
      deno cache --config nix/deno.json --no-lock nix/build_entrypoint.js
    '';

    installPhase = "true";
  };
in
stdenv.mkDerivation {
  pname = "vimium";
  inherit (manifest) version;
  src = self;

  nativeBuildInputs = [
    deno
    zip
    rsync
  ];

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p "$TMPDIR/source"
    cp -a "$src/." "$TMPDIR/source"
    chmod -R u+w "$TMPDIR/source"
    cd "$TMPDIR/source"

    export DENO_DIR='${denoDeps}'
    local flags=(
      --no-lock --allow-read --allow-write
      --allow-env --allow-run --allow-sys
    )
    deno run --config nix/deno.json "''${flags[@]}" make.js package

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    addonId='${manifest.browser_specific_settings.gecko.id}'
    dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
    mkdir -p "$dst"
    cp "$TMPDIR/source/dist/firefox/"*.zip "$dst/$addonId.xpi"

    runHook postInstall
  '';

  meta = {
    description = "The Hacker's Browser. Vimium provides keyboard shortcuts for navigation and control in the spirit of Vim.";
    homepage = "https://github.com/philc/vimium";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
