{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.notifico;

  additionalTargets = lib.optional cfg.redis.createLocally "redis-notifico.service";

  notifico-config = pkgs.writeText "local_config.py" cfg.config;

  pythonPath = pkgs.python2Packages.makePythonPath (cfg.package.propagatedBuildInputs ++ [ cfg.package ]);
in
{
  options = {
    services.notifico = {
      enable = mkEnableOption "Enable Notifico.";

      package = mkOption {
        default = pkgs.notifico;
        type = types.package;
        description = "The Notifico derivation to use.";
      };

      user = mkOption {
        default = "notifico";
        type = types.str;
        description = "The user to run under.";
      };

      group = mkOption {
        default = "notifico";
        type = types.str;
        description = "The group to run under.";
      };

      runtimeDirectory = mkOption {
        default = "notifico";
        type = types.str;
        description = "The runtime directory for Notifico.";
      };

      config = mkOption {
        default = "";
        type = types.str;
        description = "Notifico configuration to use.";
      };

      redis = {
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Redis host.";
        };

        port = mkOption {
          type = types.port;
          default = 6379;
          description = "Redis port.";
        };

        createLocally = mkOption {
          default = true;
          type = types.bool;
          description = "Configure local Redis server.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services = {
      notifico-bots = rec {
        description = "notifico bots";
        wantedBy = [ "multi-user.target" ];

        after = [ "network-online.target" ] ++ additionalTargets;
        requires = after;

        environment = {
          NOTIFICO_CONFIG_PATH = notifico-config;
        };

        serviceConfig = {
          User = cfg.user;
          Restart = "on-failure";
          RestartSec = "5s";

          ExecStart = "${cfg.package}/bin/notifico bots";
          WorkingDirectory = cfg.package;
          RuntimeDirectory = cfg.runtimeDirectory;
          StateDirectory = "notifico";
        };
      };

      notifico-www = rec {
        description = "notifico www";
        wantedBy = [ "multi-user.target" ];

        after = [ "network-online.target" ] ++ additionalTargets;
        requires = after;

        environment = {
          NOTIFICO_CONFIG_PATH = notifico-config;
          PYTHONPATH = pythonPath;
        };

        # Ugly way to get gunicorn into the environment.
        path = cfg.package.propagatedBuildInputs;

        serviceConfig = {
          User = cfg.user;
          Restart = "on-failure";
          RestartSec = "5s";

          ExecStart = ''/bin/sh -c "gunicorn 'notifico:create_instance()'"'';

          WorkingDirectory = cfg.package;
          RuntimeDirectory = cfg.runtimeDirectory;
          StateDirectory = "notifico";
        };
      };
    };

    services.redis.servers.notifico = mkIf cfg.redis.createLocally {
      enable = true;
      port = cfg.redis.port;
      bind = cfg.redis.host;
    };

    users.users.${cfg.user} = {
      group = cfg.group;
      createHome = false;
      description = "Notifico user";
      home = cfg.package;
      isSystemUser = true;
    };

    users.groups.${cfg.group} = { };
  };
}
