{
  jq,
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
    nativeBuildInputs = [
      deno
      jq
      python3
    ];
    dontUnpack = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-kXnnZvY9YmXg47leFaaEEIkmd0o8XbfL19Ni+GE1fpU=";

    buildPhase = ''
      mkdir -p "$TMPDIR/source/nix"
      cp -a "$src/nix/." "$TMPDIR/source/nix"
      cp -a "$src/deno.json" "$src/deno.lock" "$TMPDIR/source/"
      cd "$TMPDIR/source"
      export DENO_DIR="$out"
      deno cache --frozen --lock "$TMPDIR/source/deno.lock" --config deno.json nix/build_entrypoint.js
    '';

    fixupPhase = ''
      find "$out/npm" -name '.scripts-warned-*' -delete
      rm -f "$out"/dep_analysis_cache_v2* "$out"/node_analysis_cache_v2*
      find "$out/npm" -type f -name registry.json -print0 \
        | while IFS= read -r -d ''' f; do
          jq -cS '.' "$f" >"$f.tmp"
          mv "$f.tmp" "$f"
        done
      python3 "$src/nix/normalize.py" "$out"
      find "$out" -exec touch -h -d @0 {} +
    '';
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

    export DENO_DIR="$TMPDIR/deno_dir"
    mkdir -p "$DENO_DIR"
    cp -a '${denoDeps}/.' "$DENO_DIR"
    chmod -R u+w "$DENO_DIR"

    # make.js packages dist/ with `zip -r --filesync`, which stamps the current
    # wall-clock time into every archive entry and walks the staging dir in
    # readdir order (which varies from build to build). Wrap `zip` to rewrite
    # `zip -r --filesync ARCH . [-x EX...]` into `zip ARCH -@` over a
    # byte-sorted member list after rewinding file times to the epoch, so the
    # produced archive is byte-for-byte reproducible.
    realzip="$(command -v zip)"
    mkdir -p "$TMPDIR/zipwrap"
    cat > "$TMPDIR/zipwrap/zip" <<EOF
    #!/bin/sh
    if [ "\$1" != "-r" ] || [ "\$2" != "--filesync" ] || [ "\$4" != "." ]; then
      exec "$realzip" "\$@"
    fi
    archive="\$3"
    shift 4
    find . -exec touch -h -d @0 {} + 2>/dev/null || true
    find . -mindepth 1 \( -type d -printf '%p/\n' , ! -type d -print \) | LC_ALL=C sort | exec "$realzip" "\$archive" -@ "\$@"
    EOF

    chmod +x "$TMPDIR/zipwrap/zip"
    export PATH="$TMPDIR/zipwrap:$PATH"

    local flags=(
      --allow-read --allow-write
      --allow-env --allow-run --allow-sys
    )
    deno run --frozen --lock deno.lock --config deno.json "''${flags[@]}" make.js package

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
