#!/bin/sh

rsync -vrt --delete --delete-excluded nixos/ --exclude site-staging root@catircservices.org:/etc/nixos
ssh root@catircservices.org "ENVIRONMENT=production nixos-rebuild switch"
