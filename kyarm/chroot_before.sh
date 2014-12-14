#!/bin/sh -e

sudo rm -fv ${tempdir}/etc/resolv.conf || true
sudo cp -v /etc/resolv.conf ${tempdir}/etc/resolv.conf
sudo cp -v kyarm/tunslip6.c ${tempdir}/tmp/

sudo cp -vr kyarm/init.d/* ${tempdir}/etc/init.d/
sudo cp -vr kyarm/avahi/* ${tempdir}/etc/avahi/services/


sudo cp ${custom_kernel_path}/linux-headers-${custom_kernel_version}_${custom_kernel_cross}.deb ${tempdir}/tmp/ || true
sudo cp ${custom_kernel_path}/linux-firmware-image-${custom_kernel_version}_${custom_kernel_cross}.deb ${tempdir}/tmp/ || true
sudo cp ${custom_kernel_path}/linux-image-${custom_kernel_version}_${custom_kernel_cross}.deb ${tempdir}/tmp/ || true
sudo cp ${custom_kernel_path}/linux-libc-dev_${custom_kernel_cross}.deb ${tempdir}/tmp/ || true
