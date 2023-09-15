#!/bin/sh

ssh root@catircservices.org "
  nix-channel --update &&
  ENVIRONMENT=production nixos-rebuild boot &&
  reboot
"
