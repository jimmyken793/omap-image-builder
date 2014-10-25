#!/bin/sh -e

sudo rm -fv ${tempdir}/etc/resolv.conf || true
sudo cp -v /etc/resolv.conf ${tempdir}/etc/resolv.conf