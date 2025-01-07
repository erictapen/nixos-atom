{
  lib,
  fetchFromGitHub,
  applyPatches,
  buildNpmPackage,
  fetchNpmDeps,
  lessc,
  php83,
  nixosTests,
}:

let
  php = php83.buildEnv ({
    extensions = (
      { all, enabled }:
      enabled
      ++ (with all; [
        curl
        ldap
        opcache
        readline
        mbstring
        xsl
        zip
        apcu
        imagick
      ])
    );
  });
  version = "2.8.2";
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "artefactual";
      repo = "atom";
      rev = "dev/php-80-update";
      hash = "sha256-snU/yZ/5BN1lkDfAcwvl5F3wKRqEqbylcXemGbwi6P8=";
    };
    patches = [ ./unix-socket.patch ];
  };
  meta = with lib; {
    description = "Open-source, web application for archival description and public access";
    homepage = "https://accesstomemory.org/";
    changelog = "https://github.com/artefactual/atom/releases/tag/v${version}";
    license = with licenses; [ agpl3Plus ];
    platforms = platforms.linux;
    maintainers = with maintainers; [ erictapen ];
  };
  frontend = buildNpmPackage rec {
    pname = "accesstomemory-frontend";
    inherit version src meta;

    npmDepsHash = "sha256-w8526//Lm5RhlnKC7T4Wid2ymXViW1aqNSoI1N/0rb0=";

    env.CYPRESS_INSTALL_BINARY = "0"; # disallow cypress from downloading binaries in sandbox

    nativeBuildInputs = [ lessc ];

    postBuild = ''
      make -C plugins/arDominionPlugin
      make -C plugins/arArchivesCanadaPlugin
    '';

    installPhase = ''
      mkdir -p $out
      cp -r css dist js images plugins vendor $out/
    '';
  };
in
php.buildComposerProject (finalAttrs: {
  pname = "accesstomemory";
  inherit version src meta;

  composerNoDev = true;

  inherit php;

  vendorHash = "sha256-B7mccuIPSLjxKMwHn93V1WtQmpFNpkVVxRvblhXWMFE=";

  postInstall = ''
    cp -r ${frontend}/* $out/share/php/accesstomemory/
  '';

  passthru = {
    inherit frontend;
    phpPackage = php;
    tests = { inherit (nixosTests) accesstomemory; };
  };

})
