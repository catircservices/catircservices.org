{ lib, ... }:
let
  site_config = lib.importTOML (./. + "/site-${builtins.getEnv "ENVIRONMENT"}/config.toml");
  host = let
    fqdn_parts = builtins.match "([a-z]+)\\.([a-z.]+)" site_config.server_name;
  in {
    name = builtins.elemAt fqdn_parts 0;
    domain = builtins.elemAt fqdn_parts 1;
  };
in
{
  networking = {
    # Hostname
    hostName = host.name;
    domain = host.domain;

    # Services (none required; we use a static networking configuration)
    dhcpcd.enable = false;

    # Network configuration
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv6.addresses = [
          { address = site_config.net.ipv6.address; prefixLength = 64; }
          { address = site_config.irc.ipv6_prefix;  prefixLength = 96; }
        ];
        ipv6.routes = [
          { address = site_config.net.ipv6.gateway; prefixLength = 128; }
          { address = site_config.irc.ipv6_prefix;  prefixLength = 96; type = "local"; }
        ];
        ipv4.addresses = [
          { address = site_config.net.ipv4.address; prefixLength = 32; }
        ];
        ipv4.routes = [
          { address = site_config.net.ipv4.gateway; prefixLength = 32; }
        ];
      };
    };
    defaultGateway6 = { address = site_config.net.ipv6.gateway; interface = "eth0"; };
    defaultGateway = site_config.net.ipv4.gateway;
    nameservers = site_config.dns.servers;
  };
}
