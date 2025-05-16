{
  pkgs,
  certs,
  modules,
}:
{ lib, ... }:

let
  serverDomain = certs.domain;
in
{
  name = "accesstomemory";
  meta.maintainers = with lib.maintainers; [ erictapen ];

  nodes.server =
    { pkgs, lib, ... }:
    {
      imports = modules;

      virtualisation.memorySize = 4096;

      # We need development dependencies to run unit tests
      nixpkgs.overlays = [
        (final: prev: {
          accesstomemory = prev.accesstomemory.overrideAttrs (_: {
            composerNoDev = false;
          });
        })
      ];

      services.accesstomemory = {
        nable = true;
        domain = "${serverDomain}";
        title = "A very specific title";
        description = "An even more specific description";
        admin = {
          passwordFile = pkgs.writeText "insecure-password" "thisisnotapassword";
          email = "admin@${serverDomain}";
        };
      };

      services.nginx.virtualHosts."${serverDomain}" = {
        enableACME = lib.mkForce false;
        sslCertificate = certs."${serverDomain}".cert;
        sslCertificateKey = certs."${serverDomain}".key;
      };

      security.pki.certificateFiles = [ certs.ca.cert ];

      networking.hosts."::1" = [ "${serverDomain}" ];
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    };

  nodes.client =
    { pkgs, nodes, ... }:
    {
      networking.hosts."${nodes.server.networking.primaryIPAddress}" = [ "${serverDomain}" ];

      security.pki.certificateFiles = [ certs.ca.cert ];
    };

  testScript =
    { nodes }:
    let
      # Unit tests need a running database
      runUnitTests = pkgs.writeShellApplication {
        name = "run-unit-tests";
        runtimeInputs = with pkgs; [
          accesstomemory.phpPackage
          accesstomemory.phpPackage.packages.composer
          (phpunit.override { php = accesstomemory.phpPackage; })
        ];
        text = ''
          cd /var/lib/accesstomemory
          echo "Running atom unit tests..."
          composer test
        '';
      };
    in
    ''
      start_all()
      server.wait_for_unit("phpfpm-accesstomemory.service")
      server.succeed("sudo -u accesstomemory ${lib.getExe runUnitTests}")
      client.wait_for_unit("multi-user.target")
      client.succeed("curl --fail https://${serverDomain} | grep ${lib.escapeShellArg nodes.server.services.accesstomemory.title}")
      client.succeed("curl --fail https://${serverDomain} | grep ${lib.escapeShellArg nodes.server.services.accesstomemory.description}")
    '';
}
