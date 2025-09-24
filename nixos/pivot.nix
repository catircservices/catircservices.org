# Pivot required so that we use the nixpkgs from npins, instead of channels.

let
  sources = import ./npins;
  pkgs = sources.nixos;
in
  import "${pkgs}/nixos/lib/eval-config.nix" {
    system = null;

    modules = [
      ./configuration.nix
    ];
  }
