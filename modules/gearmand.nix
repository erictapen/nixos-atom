{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
  cfg = config.services.gearmand;
in
{
  options.services.gearmand = {
    enable = mkEnableOption "gearmand";
    port = mkOption {
      type = types.port;
      description = "Port on which gearmand listens";
      default = 35156;
    };
  };

  config = mkIf cfg.enable {
    users.users.gearmand = {
      isSystemUser = true;
      group = "gearmand";
    };
    users.groups.gearmand = { };

    systemd.services.gearmand = {
      description = "Gearmand";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        User = "gearmand";
        Group = "gearmand";
        ExecStart = ''
          ${lib.getExe pkgs.gearmand} \
            --daemon \
            --syslog \
            --listen 127.0.0.1 \
            --port ${toString cfg.port}
        '';
        Restart = "on-failure";
      };
    };
  };
}
