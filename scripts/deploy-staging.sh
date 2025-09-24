#!/bin/sh

rsync -vrt --delete --delete-excluded nixos/ --exclude site-production root@staging.catircservices.org:/etc/nixos
ssh root@staging.catircservices.org "ENVIRONMENT=staging nixos-rebuild switch -f /etc/nixos/pivot.nix --fast"
