#!/bin/sh

sudo apt install -y qemu-user-static

mkdir -p chrootdir/tmp chrootdir/dev chrootdir/proc sfsmnt upper/usr/bin work upper/run/systemd

# Move QEMU to the chroot directory
cp /usr/bin/qemu-aarch64-static upper/usr/bin

# Mount up the chroot
sudo mount -t squashfs *"-server-cloudimg-$1.squashfs" sfsmnt
sudo mount -t overlay overlay -olowerdir=sfsmnt,upperdir=upper,workdir=work chrootdir

sudo mount -o bind /proc chrootdir/proc/
#sudo mount -o bind /dev chrootdir/dev/
sudo mount --rbind /run/systemd chrootdir/run/systemd

# Everything below will be run inside the chroot
#####################################################################################
cat << EOF | sudo chroot chrootdir /bin/bash
sudo apt update
sudo apt install -y squashfs-tools squashfuse librsvg2-bin musl musl-tools zip golang

#wget -O /usr/bin/go $(curl -q https://api.github.com/repos/mgord9518/go.AppImage/releases | grep $(uname -m) | grep Go | grep shImg | grep browser_download_url | cut -d'"' -f4 | head -n1)
#chmod +x /usr/bin/go

wget https://raw.githubusercontent.com/mgord9518/go.AppImage/main/build.sh
sh build.sh
EOF
#####################################################################################
# Chroot end

sudo mv chrootdir/*.AppImage* chrootdir/*.shImg* ./
exit 0
