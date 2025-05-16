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
  version = "2.9.1";
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "artefactual";
      repo = "atom";
      tag = "v${version}";
      hash = "sha256-MZxvaxPJS+pyI2ezv+J7SBF3wWLYfx1ETbvwTIlaDvo=";
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

    npmDepsHash = "sha256-mOn9SAl8egwd5FpCkWf6xgNDVPii4YcLovN/83fx9SY=";

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

  # Having require-dev dependencies is only necessary to run unit tests
  vendorHash =
    if finalAttrs.composerNoDev then
      "sha256-/y1X1I+fxmtILoxOdmZvxLB9XK8Dg7KekLhVY3kfovY="
    else
      "sha256-WhPvcOL02u0G4jWKMZs4MhFRXFw5K9ryossPhRVbzss=";

  postInstall = ''
    cp -r ${frontend}/* $out/share/php/accesstomemory/
  '';

  passthru = {
    inherit frontend;
    phpPackage = php;
    tests = { inherit (nixosTests) accesstomemory; };
  };

})
