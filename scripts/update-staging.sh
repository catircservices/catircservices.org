#!/bin/sh

ssh root@staging.catircservices.org "
  nix-channel --update &&
  ENVIRONMENT=staging nixos-rebuild boot &&
  reboot
"
