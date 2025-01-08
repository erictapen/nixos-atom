{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mapAttrs
    mkDefault
    ;
  cfg = config.services.accesstomemory;
  fpm = config.services.phpfpm.pools.accesstomemory;
  package = pkgs.accesstomemory;
  path = with pkgs; [
    fop
    imagemagick
    ghostscript
    ffmpeg
    poppler_utils
  ];
in
{
  options.services.accesstomemory = {
    enable = mkEnableOption "Access to Memory (AtoM) service";
    domain = mkOption {
      description = "The domain name serving your AtoM instance.";
      example = "atom.example.org";
      type = types.str;
    };
    title = mkOption {
      description = "Site title";
      example = "AtoM";
      type = types.str;
    };
    description = mkOption {
      description = "Site description";
      example = "AtoM - Access to Memory";
      type = types.str;
    };
    admin = {
      username = mkOption {
        description = "The admin username";
        default = "admin";
        type = types.str;
      };
      passwordFile = mkOption {
        description = "File containing the admin password";
        type = types.path;
      };
      email = mkOption {
        description = "The admin email address";
        example = "admin@example.org";
        type = types.str;
      };
    };
  };

  config = lib.mkIf cfg.enable {

    services.mysql = {
      enable = true;
      settings.mysqld = {
        sql_mode = "ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES";
        optimizer_switch = "'block_nested_loop=off'";
        bind-address = "127.0.0.1";
      };
      # Recommended by upstream
      # https://www.accesstomemory.org/en/docs/2.8/admin-manual/installation/ubuntu/#mysql
      package = pkgs.percona-server_8_0;
      ensureDatabases = [ "accesstomemory" ];
      ensureUsers = [
        {
          name = "accesstomemory";
          ensurePermissions = {
            "accesstomemory.*" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    services.elasticsearch.enable = true;
    services.elasticsearch.package = pkgs.elasticsearch6;

    services.gearmand.enable = true;

    users.users.accesstomemory = {
      isSystemUser = true;
      group = "accesstomemory";
      home = "/var/lib/accesstomemory";
      packages = [ package.phpPackage ];
    };
    users.groups.accesstomemory = { };

    systemd.services.accesstomemory-install = {
      description = "Accesstomemory install";
      after = [
        "network.target"
        "elasticsearch.service"
        "mysql.service"
      ];
      path = [
        package.phpPackage
      ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "accesstomemory";
        WorkingDirectory = "/var/lib/accesstomemory";
        User = "accesstomemory";
        Group = "accesstomemory";
      };
      script = ''
        ### Delete everything except uploads/ and downloads/ and install again for now

        # Enable globbing for hidden files
        shopt -s dotglob

        for item in *; do
            base_item=$(basename "$item")

            if [[ "$base_item" == "uploads" || "$base_item" == "downloads" ]]; then
                continue
            fi

            rm -rf "$item"
        done

        cp -r ${package}/share/php/accesstomemory/* .
        chmod u+w -R .

        php -d memory_limit=4G \
          symfony tools:install \
          --database-host=localhost \
          --database-port=9999 \
          --database-name=accesstomemory \
          --database-user=accesstomemory \
          --database-password=passwordthatisnotactuallyused \
          --database-unix-socket=/run/mysqld/mysqld.sock \
          --admin-email='${cfg.admin.email}' \
          --admin-username='${cfg.admin.username}' \
          --admin-password="$(cat ${cfg.admin.passwordFile})" \
          --search-host=localhost \
          --search-port=${toString config.services.elasticsearch.port} \
          --search-index=accesstomemory \
          --site-title=${lib.escapeShellArg cfg.title} \
          --site-description=${lib.escapeShellArg cfg.description} \
          --site-base-url='https://${cfg.domain}' \
          --no-confirmation

        sed -i 's|default: 127.0.0.1:4730|default: 127.0.0.1:${toString config.services.gearmand.port}|g' config/gearman.yml

        # CSP is off by default, it's good to have it activated
        sed -i 's|Content-Security-Policy-Report-Only|Content-Security-Policy|g' config/app.yml
      '';
      restartTriggers = [ package ];
    };

    systemd.services.accesstomemory-worker = {
      description = "Accesstomemory worker";
      after = [
        "network.target"
        "accesstomemory-install.service"
        "elasticsearch.service"
        "mysql.service"
        "gearmand.service"
      ];
      requires = [ "accesstomemory-install.service" ];
      restartTriggers = [ package ];
      inherit path;
      serviceConfig = {
        Type = "simple";
        StateDirectory = "accesstomemory";
        WorkingDirectory = "/var/lib/accesstomemory";
        User = "accesstomemory";
        Group = "accesstomemory";
        ExecStart = ''
          ${lib.getExe package.phpPackage} \
            -d memory_limit=-1 \
            -d error_reporting="E_ALL" \
            symfony \
            jobs:worker
        '';
        ExecStop = "${pkgs.coreutils}/bin/kill -s TERM $MAINPID";
        Restart = "on-failure";
      };
      unitConfig = {
        # High interval and low restart limit to increase the possibility
        # of hitting the rate limits in long running recurrent jobs.
        StartLimitIntervalSec = "24h";
        StartLimitBurst = "3";
      };
    };

    services.phpfpm.pools.accesstomemory = {
      user = "accesstomemory";
      group = "accesstomemory";
      inherit (package) phpPackage;
      phpEnv = { };
      phpOptions = ''
        memory_limit = 512M
      '';
      settings = mapAttrs (name: mkDefault) {
        "listen.owner" = config.services.nginx.user;
        "listen.group" = config.services.nginx.group;

        # Let's follow upstreams recommendations exactly for now
        # https://www.accesstomemory.org/en/docs/2.8/admin-manual/installation/ubuntu/#php-fpm
        "pm" = "dynamic";
        "pm.max_children" = "30";
        "pm.start_servers" = "10";
        "pm.min_spare_servers" = "10";
        "pm.max_spare_servers" = "10";
        "pm.max_requests" = "200";

        "chdir" = "/";

        "php_admin_value[expose_php]" = "off";
        "php_admin_value[allow_url_fopen]" = "on";
        "php_admin_value[memory_limit]" = "512M";
        "php_admin_value[max_execution_time]" = "120";
        "php_admin_value[post_max_size]" = "72M";
        "php_admin_value[upload_max_filesize]" = "64M";
        "php_admin_value[max_file_uploads]" = "10";
        "php_admin_value[cgi.fix_pathinfo]" = "0";
        "php_admin_value[display_errors]" = "off";
        "php_admin_value[display_startup_errors]" = "off";
        "php_admin_value[html_errors]" = "off";
        "php_admin_value[session.use_only_cookies]" = "0";

        "php_admin_value[apc.enabled]" = "1";
        "php_admin_value[apc.shm_size]" = "64M";
        "php_admin_value[apc.num_files_hint]" = "5000";
        "php_admin_value[apc.stat]" = "0";

        "php_admin_value[opcache.enable]" = "1";
        "php_admin_value[opcache.memory_consumption]" = "192";
        "php_admin_value[opcache.interned_strings_buffer]" = "16";
        "php_admin_value[opcache.max_accelerated_files]" = "4000";
        "php_admin_value[opcache.validate_timestamps]" = "0";
        "php_admin_value[opcache.fast_shutdown]" = "1";
      };
    };
    systemd.services.phpfpm-accesstomemory = {
      requires = [
        "accesstomemory-install.service"
        "accesstomemory-worker.service"
      ];
      after = [
        "mysql.service"
        "elasticsearch.service"
        "accesstomemory-install.service"
        "accesstomemory-worker.service"
      ];
      restartTriggers = [ package ];
      inherit path;
    };

    services.nginx.enable = true;
    # https://www.accesstomemory.org/en/docs/2.8/admin-manual/installation/ubuntu/#nginx
    services.nginx.virtualHosts."${cfg.domain}" = {
      root = "/var/lib/accesstomemory";
      extraConfig = ''
        client_max_body_size 72M;
      '';
      locations = {
        "~* ^/(css|dist|js|images|plugins|vendor)/.*\\.(css|png|jpg|js|svg|ico|gif|pdf|woff|woff2|ttf)$" = {
          root = "/var/lib/accesstomemory";
        };
        "~* ^/(downloads)/.*\\.(pdf|xml|html|csv|zip|rtf)$" = { };
        "~ ^/(ead.dtd|favicon.ico|robots.txt|sitemap.*)$" = { };
        "/" = {
          tryFiles = "$uri /index.php?$args";
          extraConfig = ''
            if (-f $request_filename) {
              return 403;
            }
          '';
        };
        "~* /uploads/r/(.*)/conf/" = { };
        "~* ^/uploads/r/(.*)$" = {
          extraConfig = ''
            include ${config.services.nginx.package}/conf/fastcgi.conf;
            set $index /index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$index;
            fastcgi_param SCRIPT_NAME $index;
            fastcgi_pass unix:${fpm.socket};
          '';
        };
        "~ ^/private/(.*)$" = {
          extraConfig = ''
            internal;
            alias /var/lib/accesstomemory/$1;
          '';
        };
        "~ ^/(index|qubit_dev)\\.php(/|$)" = {
          extraConfig = ''
            include ${config.services.nginx.package}/conf/fastcgi.conf;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_split_path_info ^(.+\.php)(/.*)$;
            fastcgi_pass unix:${fpm.socket};
          '';
        };
      };
      forceSSL = true;
      enableACME = true;
    };

  };
}
