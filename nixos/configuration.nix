{ pkgs, lib, config, ... }:
let
  site_config = lib.importTOML ./site-${builtins.getEnv "ENVIRONMENT"}/config.toml;
  site_secrets = lib.importTOML ./site-${builtins.getEnv "ENVIRONMENT"}/secrets.toml;
in {
  system.stateVersion = "23.05";

  # System
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  # Hostname
  networking.hostName = builtins.elemAt (builtins.split "\\." site_config.server_name) 0;
  networking.domain = builtins.elemAt (builtins.split "\\." site_config.server_name) 2;

  # SSH
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = site_config.ssh.pubkeys;

  # Database
  services.postgresql = {
    enable = true;
    initialScript = pkgs.writeText "database-init.sql" ''
      CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
      CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
        TEMPLATE template0
        LC_COLLATE = "C"
        LC_CTYPE = "C";
      CREATE ROLE "matrix-appservice-irc" WITH LOGIN PASSWORD 'irc';
      CREATE DATABASE "matrix-appservice-irc" WITH OWNER "matrix-appservice-irc";
      CREATE ROLE "grafana" WITH LOGIN PASSWORD 'grafana';
      CREATE DATABASE "grafana" WITH OWNER "grafana";
    '';
  };

  # Database backup
  services.postgresqlBackup = {
    enable = site_config.backup.enable;
    compression = "zstd";
    databases = ["matrix-synapse" "matrix-appservice-irc" "grafana"];
  };

  # Matrix homeserver
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = site_config.server_name;
      listeners = [
        {
          port = 8008;
          bind_addresses = ["::1"];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [{
            names = ["client" "federation"];
            compress = true;
          }];
        }
        {
          port = 8018;
          bind_addresses = ["::1"];
          type = "http";
          tls = false;
          resources = [{
            names = ["metrics"];
            compress = true;
          }];
        }
      ];
      app_service_config_files = [
        "/var/lib/matrix-appservice-irc/registration.yml"
      ];
      enable_metrics = site_config.metrics.enable;
      enable_registration = site_config.matrix.registration;
      enable_registration_without_verification = site_config.matrix.registration;
    };
  };

  # Matrix IRC appservice
  boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = "1";
  services.matrix-appservice-irc = {
    enable = true;
    needBindingCap = true; # to bind to ident on 113

    port = 8009;
    registrationUrl = "http://localhost:8009";

    settings = {
      database = {
        engine = "postgres";
        connectionString = "postgres://matrix-appservice-irc:irc@localhost/matrix-appservice-irc";
      };
      homeserver = {
        url = "http://[::1]:8008";
        media_url = "https://${site_config.server_name}";
        domain = site_config.server_name;
        bindPort = 8009;
        bindHostname = "::1";
        dropMatrixMessagesAfterSecs = 600; # 10 minutes
      };
      ircService = {
        servers."irc.libera.chat" = {
          name = "libera.chat";
          additionalAddresses = ["irc.eu.libera.chat"];
          onlyAdditionalAddresses = true;
          port = 6697;
          ssl = true;
          botConfig = {
            nick = site_config.irc.bot_nickname;
            username = site_config.irc.bot_username;
            password = site_secrets.irc.bot_password;
          };
          membershipLists = {
            enabled = true;
            global = {
              ircToMatrix = {
                initial = true;
                incremental = true;
                # See [Note 1].
                requireMatrixJoined = false;
              };
              matrixToIrc = {
                initial = true;
                incremental = true;
              };
            };
            ignoreIdleUsersOnStartup = {
              enabled = true;
              idleForHours = 24*7;
            };
          };
          rooms = (site_config.irc.rooms ++ site_secrets.irc.rooms);
          channels = (site_config.irc.channels ++ site_secrets.irc.channels);
          mappings = lib.mkMerge [site_config.irc.mappings site_secrets.irc.mappings];
          matrixClients = {
            userTemplate = "@libera_$NICK";
          };
          ircClients = {
            nickTemplate = "$DISPLAY[m]";
            allowNickChanges = true;
            maxClients = 0;
            ipv6.prefix = site_config.irc.ipv6_prefix;
            # See [Note 1].
            kickOn = {
              channelJoinFailure = false;
              ircConnectionFailure = false;
              userQuit = false;
            };
          };
        };
        ident.enabled = true;
        metrics.enabled = site_config.metrics.enable;
        debugApi = {
          enabled = true;
          port = 11100;
        };
      };
    };
    # [Note 1]: We only bridge Matrix channels that are public and/or where chanops have explicitly
    # opted into the mode in which this bridge is operating, where Matrix users are not
    # continuously reflected on the IRC side.
  };

  # Prometheus
  services.prometheus = {
    enable = site_config.metrics.enable;
    listenAddress = "[::1]";
    port = 9090;
    scrapeConfigs = [
      {
        job_name = "matrix-synapse";
        scrape_interval = "15s";
        scrape_timeout = "15s";
        metrics_path = "/_synapse/metrics";
        scheme = "http";
        static_configs = [
          {
            targets = ["[::1]:8018"];
            labels = {
              instance = site_config.server_name;
              index = "1";
            };
          }
        ];
      }
      {
        job_name = "matrix-appservice-irc";
        scrape_interval = "15s";
        scrape_timeout = "15s";
        metrics_path = "/metrics";
        scheme = "http";
        static_configs = [
          {
            targets = ["[::1]:8009"];
            labels = {
              instance = site_config.server_name;
            };
          }
        ];
      }
    ];
    rules = [''
groups:
- name: synapse
  rules:
  - record: synapse_storage_events_persisted_by_source_type
    expr: sum without(type, origin_type, origin_entity) (synapse_storage_events_persisted_events_sep_total{origin_type="remote"})
    labels:
      type: remote
  - record: synapse_storage_events_persisted_by_source_type
    expr: sum without(type, origin_type, origin_entity) (synapse_storage_events_persisted_events_sep_total{origin_entity="*client*",origin_type="local"})
    labels:
      type: local
  - record: synapse_storage_events_persisted_by_source_type
    expr: sum without(type, origin_type, origin_entity) (synapse_storage_events_persisted_events_sep_total{origin_entity!="*client*",origin_type="local"})
    labels:
      type: bridges

  - record: synapse_storage_events_persisted_by_event_type
    expr: sum without(origin_entity, origin_type) (synapse_storage_events_persisted_events_sep_total)

  - record: synapse_storage_events_persisted_by_origin
    expr: sum without(type) (synapse_storage_events_persisted_events_sep_total)
    ''];
  };

  # Grafana
  services.grafana = {
    enable = site_config.metrics.enable;
    settings = {
      database = {
        type = "postgres";
        host = "localhost";
        user = "grafana";
        password = "grafana";
      };
      server = {
        http_addr = "::1";
        http_port = 9000;
        root_url = "/metrics/";
      };
      feature_toggles = {
        enable = "publicDashboards";
      };
    };
  };

  # TLS certificates
  security.acme = {
    acceptTerms = true;
    defaults = { email = site_config.web.acme_email; };
  };
  users.users.nginx.extraGroups = ["acme"];

  # Web reverse proxy server
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;

    virtualHosts = {
      "${site_config.server_name}" = {
        listen = [
          {addr = "0.0.0.0"; port =   80; ssl = false;}
          {addr = "[::]";    port =   80; ssl = false;}
          {addr = "0.0.0.0"; port =  443; ssl = true;}
          {addr = "[::]";    port =  443; ssl = true;}
          {addr = "0.0.0.0"; port = 8448; ssl = true;}
          {addr = "[::]";    port = 8448; ssl = true;}
        ];

        forceSSL = true;
        enableACME = true;

        extraConfig = "
          merge_slashes off;
        ";

        # HTML banner at the root
        locations."=/".extraConfig = "
          default_type text/html;
          charset utf-8;
          return 200 \"${builtins.replaceStrings ["\n" "\""] ["\\n" "\\\""] site_config.web.banner}\";
        ";

        # Matrix homeserver proxy
        locations."/_matrix/" = {
          proxyPass = "http://[::1]:8008$request_uri";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Host $host;
            proxy_hide_header Content-Disposition; # matrix-org/synapse#15885
            proxy_buffering off;
          '';
        };

        # Grafana matrics
        locations."/metrics/" = {
          proxyPass = "http://[::1]:9000/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
          '';
        };
      };
    };
  };

  # Firewall
  networking.firewall = {
    allowedTCPPorts = [ 80 443 8448 113 ];
    allowedUDPPorts = [ 80 443 8448 113 ];
  };

  # Backup
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["tarsnap"];
  services.tarsnap = {
    enable = site_config.backup.enable;
    keyfile = "${pkgs.writeText "tarsnap.key" site_secrets.tarsnap.keyfile}";
    archives."${site_config.server_name}" = {
      directories = [
        "/etc/nixos"
        "/var/backup"
        "/var/lib/matrix-synapse"
        "/var/lib/matrix-appservice-irc"
        "/var/lib/prometheus2"
      ];
      # Unclear if these excludes would cause issues restoring or not.
      # This has been undocumented since 2017 (!), see matrix-org/synapse#2046.
      # excludes = [
      #   "/var/lib/matrix-synapse/media_store/url_cache*"
      #   "/var/lib/matrix-synapse/media_store/*_thumbnail*"
      #   "/var/lib/matrix-synapse/media_store/remote_*"
      # ];
    };
  };
}
