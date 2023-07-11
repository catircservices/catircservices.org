{ pkgs, lib, config, ... }:
let
  site_config = lib.importTOML ./site/config.toml;
  site_secrets = lib.importTOML ./site/secrets.toml;
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
  users.users.root.openssh.authorizedKeys.keys = [ site_config.ssh.pubkey ];

  # Database
  services.postgresql = {
    enable = true;
    initialScript = pkgs.writeText "synapse-init.sql" ''
      CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
      CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
        TEMPLATE template0
        LC_COLLATE = "C"
        LC_CTYPE = "C";
      CREATE ROLE "matrix-appservice-irc" WITH LOGIN PASSWORD 'appservice-irc';
      CREATE DATABASE "matrix-appservice-irc" WITH OWNER "matrix-appservice-irc";
    '';
  };

  # Database backup
  services.postgresqlBackup = {
    enable = true;
    compression = "zstd";
  };

  # Matrix homeserver
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = site_config.server_name;
      listeners = [{
        port = 8008;
        bind_addresses = ["::1"];
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [{
          names = ["client" "federation"];
          compress = true;
        }];
      }];
      app_service_config_files = [
        "/var/lib/matrix-appservice-irc/registration.yml"
      ];
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
        connectionString = "postgres://matrix-appservice-irc:appservice-irc@localhost/matrix-appservice-irc";
      };
      homeserver = {
        url = "http://[::1]:8008";
        media_url = "https://${site_config.server_name}";
        domain = site_config.server_name;
        bindPort = 8009;
        bindHostname = "::1";
      };
      ircService = {
        servers."irc.libera.chat" = {
          name = "libera.chat";
          port = 6697;
          ssl = true;
          botConfig = {
            nick = site_config.irc.bot_username;
            username = site_config.irc.bot_username;
            password = site_secrets.irc.bot_password;
          };
          membershipLists = {
            enabled = true;
            global = {
              ircToMatrix = {
                initial = true;
                incremental = true;
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
          mappings = site_secrets.irc.rooms;
          matrixClients = {
            userTemplate = "@libera_$NICK";
          };
          ircClients = {
            nickTemplate = "$DISPLAY[m]";
            allowNickChanges = true;
            ipv6.prefix = site_config.irc.ipv6_prefix;
          };
        };
        ident.enabled = true;
      };
    };
  };

  # TLS certificates
  security.acme = {
    acceptTerms = true;
    defaults = { email = site_config.admin_email; };
  };
  users.users.nginx.extraGroups = [
    "acme"
  ];

  # Web reverse proxy server
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;

    virtualHosts = {
      "${site_config.server_name}" = {
        listen = [
          {addr = "*"; port = 80; ssl = false;}
          {addr = "*"; port = 443; ssl = true;}
          {addr = "*"; port = 8448; ssl = true;}
        ];

        forceSSL = true;
        enableACME = true;

        extraConfig = "
          merge_slashes off;
        ";

        # HTML banner at the root
        locations."=/".extraConfig = "
          add_header Content-Type text/html;
          return 200 \"${site_config.web.banner}\";
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

      };
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 8448 113 ];
  networking.firewall.allowedUDPPorts = [ 80 443 8448 113 ];
}
