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
      # dev/php-80-update
      rev = "fc248cb849c9fa0287115a3fdf928e39c748688c";
      hash = "sha256-BR8fxedVB4tOM+iwsTg0MedoOHXirGAoGBuhdJorjNs=";
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

    npmDepsHash = "sha256-9BkNqE9CFaudzMAdpiEU3792/smy+gTeLKvVRpUA+VU=";

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
