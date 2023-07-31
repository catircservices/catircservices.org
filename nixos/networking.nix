{ lib, ... }:
let
  siteConfig = lib.importTOML (./. + "/site-${builtins.getEnv "ENVIRONMENT"}/config.toml");
  host = let
    fqdnParts = builtins.match "([a-z]+)\\.([a-z.]+)" siteConfig.serverName;
  in {
    name = builtins.elemAt fqdnParts 0;
    domain = builtins.elemAt fqdnParts 1;
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
          { address = siteConfig.net.ipv6.address; prefixLength = 64; }
          { address = siteConfig.irc.ipv6Prefix;   prefixLength = 96; }
        ];
        ipv6.routes = [
          { address = siteConfig.net.ipv6.gateway; prefixLength = 128; }
          { address = siteConfig.irc.ipv6Prefix;   prefixLength = 96; type = "local"; }
        ];
        ipv4.addresses = [
          { address = siteConfig.net.ipv4.address; prefixLength = 32; }
        ];
        ipv4.routes = [
          { address = siteConfig.net.ipv4.gateway; prefixLength = 32; }
        ];
      };
    };
    defaultGateway6 = { address = siteConfig.net.ipv6.gateway; interface = "eth0"; };
    defaultGateway = siteConfig.net.ipv4.gateway;
    nameservers = siteConfig.dns.servers;
  };
}
