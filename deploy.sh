#!/bin/sh

rsync -vrt --delete nixos/ root@catircservices.org:/etc/nixos
ssh root@catircservices.org "nixos-rebuild switch"
