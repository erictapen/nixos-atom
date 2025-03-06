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
      # qa/2.x branch
      rev = "69a949dfa96fcce7a8ef70657b4d893673094a6b";
      hash = "sha256-4fEAeoAjivmhi+DDg18sD/6El6HDNwb0RlYGzNu2oCk=";
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
