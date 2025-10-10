{ pkgs, lib, config, ... }:
let
  siteConfig = lib.importTOML (./. + "/site-${builtins.getEnv "ENVIRONMENT"}/config.toml");
  siteSecrets = lib.importTOML (./. + "/site-${builtins.getEnv "ENVIRONMENT"}/secrets.toml");

  notifico = pkgs.callPackage ./pkgs/notifico { };
in {
  system.stateVersion = "23.05";

  # System
  imports = [
    ./modules/notifico.nix
    ./hardware-configuration.nix
    ./networking.nix
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  # Prompt
  programs.bash.promptInit = ''
    if [ "$TERM" != "dumb" ]; then
      PS1="\n\[\033[${siteConfig.promptColor}m\][\u@${siteConfig.serverName}:\w]\\$\[\033[0m\] "
    fi
  '';

  # Nix overlays and configuration
  nix = {
    gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };

    settings = {
      experimental-features = "flakes nix-command";
    };
  };

  nixpkgs = {
    config.permittedInsecurePackages = [
      "openssl-1.1.1w"
      "python-2.7.18.8"
    ];

    flake.source = (import ./npins).nixos;

    hostPlatform = lib.mkDefault "aarch64-linux";
  };

  # SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };
  users.users.root.openssh.authorizedKeys.keys = siteConfig.ssh.pubkeys;

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
    enable = siteConfig.backup.enable;
    compression = "none";
    databases = ["matrix-synapse" "matrix-appservice-irc" "grafana"];
  };

  # Matrix homeserver
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = siteConfig.serverName;
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
          port = 8108;
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
        "/var/lib/matrix-appservice-discord/discord-registration.yaml"
      ];
      enable_metrics = siteConfig.metrics.enable;
      enable_registration = siteConfig.matrix.registration;
      enable_registration_without_verification = siteConfig.matrix.registration;
      use_appservice_legacy_authorization = true;
    };
  };

  # Ensure CPU/memory metrics work on Synapse
  # (the Prometheus client reads /proc/stat to prove it can read the metrics)
  systemd.services.matrix-synapse.serviceConfig.ProcSubset = lib.mkForce "all";

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
        media_url = "https://${siteConfig.serverName}";
        domain = siteConfig.serverName;
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
            nick = siteConfig.irc.botNickname;
            username = siteConfig.irc.botUsername;
            password = siteSecrets.irc.botPassword;
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
                # We have too many (idle) users on the Matrix side to realistically sync.
                initial = false;
                incremental = false;
              };
            };
            ignoreIdleUsersOnStartup = {
              enabled = true;
              idleForHours = 24*7;
            };
          };
          rooms = (siteConfig.irc.rooms ++ siteSecrets.irc.rooms);
          channels = (siteConfig.irc.channels ++ siteSecrets.irc.channels);
          mappings = lib.mkMerge [siteConfig.irc.mappings siteSecrets.irc.mappings];
          matrixClients = {
            userTemplate = "@libera_$NICK";
          };
          ircClients = {
            nickTemplate = "$DISPLAY[m]";
            allowNickChanges = true;
            maxClients = 0;
            ipv6.prefix = siteConfig.irc.ipv6Prefix;
            # See [Note 1].
            kickOn = {
              channelJoinFailure = false;
              ircConnectionFailure = false;
              userQuit = false;
            };
          };
        };
        matrixHandler = {
          shortReplyTemplate = "$NICK: $REPLY";
          longReplyTemplate = "<$NICK> $ORIGINAL\n$REPLY";
          # the typo is intentional
          shortReplyTresholdSeconds = 400;
          replySourceMaxLength = 300;
        };
        mediaProxy = {
          bindPort = 8007;
          publicUrl = "https://${siteConfig.serverName}/_irc/";
          ttlSeconds = 0;
        };
        perRoomConfig = {
          enabled = true;
          lineLimitMax = 12;
          allowUnconnectedMatrixUsers = false; # don't allow overwriting allowUnconnectedMatrixUsers
        };
        ident.enabled = true;
        metrics.enabled = siteConfig.metrics.enable;
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

  # Matrix Discord appservice
  services.matrix-appservice-discord = rec {
    enable = true;
    package = pkgs.matrix-appservice-discord.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or []) ++ [
        (pkgs.fetchpatch {
          url = "https://github.com/luc14n0/matrix-appservice-discord/commit/998620daf468e766c726c9dd8807054929126bd1.patch";
          hash = "sha256-7iQuUcaNa+WVyYbVSRytDDeqJsg3069iZCYb8D2itnM=";
        })
      ];
    });
    port = 8010;
    url = "http://localhost:8010";
    settings = {
      bridge = {
        domain = siteConfig.serverName;
        homeserverUrl = "https://${siteConfig.serverName}/";
        disablePresence = true;
        disablePortalBridging = true;
        enableSelfServiceBridging = siteConfig.discord.selfServiceBridging;
        disableJoinLeaveNotifications = true;
        adminMxid = siteConfig.discord.adminMxid;
      };
      ghosts = {
        nickPattern = ":nick";
      };
      auth = {
        clientID = siteConfig.discord.applicationId;
        botToken = siteSecrets.discord.botToken;
        usePrivilegedIntents = true;
      };
      metrics = {
        enable = siteConfig.metrics.enable;
        port = 8110;
      };
    };
  };
  # fix some batshit defaults that break the deployment entirely
  users.groups.matrix-appservice-discord = {};
  users.users.matrix-appservice-discord = {
    description = "Service user for the Matrix-Discord bridge";
    group = "matrix-appservice-discord";
    isSystemUser = true;
  };
  systemd.services.matrix-appservice-discord.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "matrix-appservice-discord";
    Group = "matrix-appservice-discord";
    StateDirectory = "matrix-appservice-discord";
    StateDirectoryMode = "755";
    UMask = lib.mkForce "0022";
  };

  # Prometheus
  services.prometheus = {
    enable = siteConfig.metrics.enable;
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
            targets = ["[::1]:8108"];
            labels = {
              instance = siteConfig.serverName;
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
              instance = siteConfig.serverName;
            };
          }
        ];
      }
      {
        job_name = "matrix-appservice-discord";
        scrape_interval = "15s";
        scrape_timeout = "15s";
        metrics_path = "/metrics";
        scheme = "http";
        static_configs = [
          {
            targets = ["[::1]:8110"];
            labels = {
              instance = siteConfig.serverName;
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
    enable = siteConfig.metrics.enable;
    settings = {
      database = {
        type = "postgres";
        host = "localhost";
        user = "grafana";
        # silence a warning about plaintext passwords being stored in Nix store
        password = "$__file{${pkgs.writeText "grafana_database_password" "grafana"}}";
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
    defaults = { email = siteConfig.web.acmeEmail; };
  };
  users.users.nginx.extraGroups = ["acme"];

  # Web reverse proxy server
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    clientMaxBodySize = "25m";

    virtualHosts = {
      "${siteConfig.serverName}" = {
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
          return 200 \"${builtins.replaceStrings ["\n" "\""] ["\\n" "\\\""] siteConfig.web.banner}\";
        ";

        # Matrix homeserver proxy
        locations."/_matrix/" = {
          proxyPass = "http://[::1]:8008$request_uri";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Host $host;
            proxy_buffering off;
          '';
        };

        # Matrix IRC media proxy
        locations."/_irc/" = {
          proxyPass = "http://127.0.0.1:8007/";
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
    } // lib.optionalAttrs siteConfig.notifico.enable {
      "notifico.${siteConfig.serverName}" = {
        forceSSL = true;
        enableACME = true;

        locations."/".extraConfig = ''
          root "${notifico}/lib/python2.7/site-packages/notifico/static";

          try_files $uri @notifico;
        '';

        locations."@notifico" = {
          proxyPass = "http://127.0.0.1:8000";

          extraConfig = ''
            proxy_set_header Host $host;
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
  services.restic.backups = lib.mkIf siteConfig.backup.restic {
    all = {
      repository = siteSecrets.restic.repository;
      passwordFile = "${pkgs.writeText "password" siteSecrets.restic.password}";
      environmentFile = "${pkgs.writeText "environment" siteSecrets.restic.environment}";
      initialize = true;
      paths = [
        "/etc/nixos"
        "/var/backup"
        "/var/lib/matrix-synapse"
        "/var/lib/matrix-appservice-irc"
        "/var/lib/matrix-appservice-discord"
      ];
    };
  };

  # Notifico
  services.notifico = lib.mkIf siteConfig.notifico.enable {
    enable = true;
    package = notifico;

    config = siteSecrets.notifico.config;
  };
}
