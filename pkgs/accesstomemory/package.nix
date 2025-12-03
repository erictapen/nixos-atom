{
  lib,
  fetchFromGitHub,
  applyPatches,
  buildNpmPackage,
  fetchNpmDeps,
  php83,
  nixosTests,
  composerNoDev ? true,
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
        memcache
      ])
    );
  });
  version = "2.10.1";
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "artefactual";
      repo = "atom";
      tag = "v${version}";
      hash = "sha256-M4k0BeYiQpNtOurldGHJMpAMJIBkpBSxUQDUtQEJUE4=";
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

    npmDepsHash = "sha256-SJnEFRVEib732um/2+3FT8DFhr+RQKtGOszPSqLJoK0=";

    env.CYPRESS_INSTALL_BINARY = "0"; # disallow cypress from downloading binaries in sandbox

    installPhase = ''
      mkdir -p $out
      cp -r css dist js images plugins vendor $out/
    '';
  };
in
php.buildComposerProject (finalAttrs: {
  pname = "accesstomemory";
  inherit version src meta;

  inherit composerNoDev;

  inherit php;

  composerRepository = php.mkComposerRepository {
    inherit (finalAttrs)
      patches
      pname
      src
      version
      ;
    composer = php.packages.composer-local-repo-plugin;

    # Having require-dev dependencies is only necessary to run unit tests
    vendorHash =
      if finalAttrs.composerNoDev then
        "sha256-yG732HZy+0okcEET88KiWMSswjnF0Zg1FGGqzQL2zFA="
      else
        "sha256-pnIwei141zY2SnK2fzoNVeL8FGHxDeHyy6e24buaq8g=";

    composerLock = finalAttrs.composerLock or null;
    inherit composerNoDev;
    composerNoPlugins = finalAttrs.composerNoPlugins or true;
    composerNoScripts = finalAttrs.composerNoScripts or true;
    composerStrictValidation = finalAttrs.composerStrictValidation or true;
  };

  postInstall = ''
    cp -r ${frontend}/* $out/share/php/accesstomemory/
  '';

  passthru = {
    inherit frontend;
    phpPackage = php;
    tests = { inherit (nixosTests) accesstomemory; };
  };

})
