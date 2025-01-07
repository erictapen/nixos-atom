# Taken from https://github.com/NixOS/nixpkgs/commit/09a6672bbfc240b6154474b135ba583c929859e4#diff-f449cfb4f2ccb078f799c6980ed18e19cf6d643485fea9579125b81e664b73f0
# with minor changes

{
  elk6Version,
  enableUnfree ? true,
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  jre_headless,
  util-linux,
  gnugrep,
  coreutils,
  libxcrypt-legacy,
  autoPatchelfHook,
  zlib,
}:

with lib;

stdenv.mkDerivation (
  rec {
    version = elk6Version;
    pname = "elasticsearch${optionalString (!enableUnfree) "-oss"}";

    src = fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${pname}-${version}.tar.gz";
      sha256 =
        if enableUnfree then
          "sha256-Qkr5H4OPnl8T4Ckvl8vWMzU1RQKRpiHXYb1Hnfwt/3g="
        else
          "sha256-YOd7XKPOEXcUabzC4AnEnIqtuDH669Fw56vO3Baz420=";
    };

    patches = [ ./es-home-6.x.patch ];

    postPatch = ''
      substituteInPlace bin/elasticsearch-env --replace \
        "ES_CLASSPATH=\"\$ES_HOME/lib/*\"" \
        "ES_CLASSPATH=\"$out/lib/*\""

      substituteInPlace bin/elasticsearch-cli --replace \
        "ES_CLASSPATH=\"\$ES_CLASSPATH:\$ES_HOME/\$additional_classpath_directory/*\"" \
        "ES_CLASSPATH=\"\$ES_CLASSPATH:$out/\$additional_classpath_directory/*\""
    '';

    nativeBuildInputs = [ makeWrapper ];
    buildInputs =
      [
        jre_headless
        util-linux
      ]
      ++ optionals enableUnfree [
        zlib
        libxcrypt-legacy
      ];

    installPhase = ''
      mkdir -p $out
      cp -R bin config lib modules plugins $out

      chmod -x $out/bin/*.*

      wrapProgram $out/bin/elasticsearch \
        --prefix PATH : "${
          makeBinPath [
            util-linux
            gnugrep
            coreutils
          ]
        }" \
        --set JAVA_HOME "${jre_headless}"

      wrapProgram $out/bin/elasticsearch-plugin --set JAVA_HOME "${jre_headless}"
    '';

    passthru = { inherit enableUnfree; };

    meta = {
      description = "Open Source, Distributed, RESTful Search Engine";
      sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
      license = if enableUnfree then licenses.elastic20 else licenses.asl20;
      platforms = platforms.unix;
      maintainers = with maintainers; [
        apeschar
        basvandijk
      ];
    };
  }
  // optionalAttrs enableUnfree {
    dontPatchELF = true;
    nativeBuildInputs = [ makeWrapper ] ++ optional stdenv.isLinux autoPatchelfHook;
    runtimeDependencies = [ zlib ];
    postFixup = lib.optionalString stdenv.isLinux ''
      for exe in $(find $out/modules/x-pack-ml/platform/linux-x86_64/bin -executable -type f); do
        echo "patching $exe..."
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$exe"
      done
    '';
  }
)
