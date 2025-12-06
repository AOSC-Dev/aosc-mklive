#!/bin/bash
# New LiveKit generator.
# This "new" LiveKit will use our dracut loader to load the LiveKit.
set -e
source lib.bash

# Set of '--topics TOPIC' options to be passed to aoscbootstrap.
TOPICS_OPT=

WORKDIR=${PWD}/work
ISODIR=${PWD}/iso
AOSCBOOTSTRAP=${AOSCBOOTSTRAP:-/usr/share/aoscbootstrap}
FSTYPE=${FSTYPE:-squashfs}
OUT_PREFIX="$ISODIR"/livekit

info "Generating LiveKit distribution ..."

info "Preparing ..."
rm -rf iso work
mkdir -p $WORKDIR/livekit
mkdir -p $ISODIR/livekit
# We have to pack up the dracut module and copy into the target sysroot
# where it will be untarred and installed into initrd.
tar cf $WORKDIR/livekit/dracut.tar dracut

info "Bootstrapping LiveKit tarball ..."
_cnt=0
if [ "x$TOPICS" != "x" ] ; then
	for t in $TOPICS ; do
		info "Will opt in Topic '$t'."
		TOPIC_OPTS="$TOPIC_OPTS --topics $t"
		_cnt=$(($cnt + 1))
	done
fi
if [ "$_cnt" -gt 0 ] ; then
	info "Opted in $_cnt topic(s)."
fi

info "Invoking aoscbootstrap ..."
if [[ "${ARCH}" = "loongarch64" ]]; then
	echo "Generating LiveKit distribution (loongarch64) ..."
	aoscbootstrap \
		--branch ${BRANCH:-stable} \
		--target $WORKDIR/livekit \
		--mirror ${REPO:-https://repo.aosc.io/debs} \
		--config /usr/share/aoscbootstrap/config/aosc-mainline.toml \
		-x --force \
		$TOPIC_OPTS \
		--arch ${ARCH:-$(dpkg --print-architecture)} \
		-s /usr/share/aoscbootstrap/scripts/reset-repo.sh \
		-s /usr/share/aoscbootstrap/scripts/enable-nvidia-drivers.sh \
		-s /usr/share/aoscbootstrap/scripts/enable-dkms.sh \
		-s "$PWD/scripts/livekit.sh" \
		-s "$PWD/scripts/loongarch64-tweaks.sh" \
		--include-files "$PWD/recipes/livekit.lst"
elif [[ "${RETRO}" != "1" ]]; then
	echo "Generating LiveKit distribution ..."
	aoscbootstrap \
		--branch ${BRANCH:-stable} \
		--target $WORKDIR/livekit \
		--mirror ${REPO:-https://repo.aosc.io/debs} \
		--config /usr/share/aoscbootstrap/config/aosc-mainline.toml \
		-x --force \
		--arch ${ARCH:-$(dpkg --print-architecture)} \
		$TOPIC_OPTS \
		-s /usr/share/aoscbootstrap/scripts/reset-repo.sh \
		-s /usr/share/aoscbootstrap/scripts/enable-nvidia-drivers.sh \
		-s /usr/share/aoscbootstrap/scripts/enable-dkms.sh \
		-s "$PWD/scripts/livekit.sh" \
		--include-files "$PWD/recipes/livekit.lst"
else
	echo "Generating Retro LiveKit distribution ..."
	aoscbootstrap \
		--branch ${BRANCH:-stable} \
		--target $WORKDIR/livekit \
		--mirror ${REPO:-https://repo.aosc.io/debs} \
		--config /usr/share/aoscbootstrap/config/aosc-retro.toml \
		-x --force \
		--arch ${ARCH:-$(dpkg --print-architecture)} \
		$TOPIC_OPTS \
		-s "$PWD/scripts/retro-livekit.sh" \
		--include-files "$PWD/recipes/retro-livekit.lst"
fi

echo "Extracting LiveKit kernel/initramfs ..."
mkdir -pv "$ISODIR"/boot
cp -v "$WORKDIR"/livekit/kernel "$ISODIR"/boot/kernel
cp -v "$WORKDIR"/livekit/live-initramfs.img "$ISODIR"/boot/live-initramfs.img
rm -v "$WORKDIR"/livekit/kernel "$WORKDIR"/livekit/live-initramfs.img
if [ "$ARCH" = "loongson3" ] ; then
	cp -v "$WORKDIR"/livekit/live-initramfs-lite.img "$ISODIR"/boot/minird.img
	rm -v "$WORKDIR"/livekit/live-initramfs-lite.img
fi

if [[ "${RETRO}" != "1" ]]; then
	echo "Copying LiveKit template ..."
	chown -vR 0:0 templates/livekit/*
	cp -av templates/livekit/* $WORKDIR/livekit/
	chown -vR 1000:1001 $WORKDIR/livekit/home/live
	if [ "$SUDO_UID" != 0 ] ; then
		chown -vR $SUDO_UID:$SUDO_GID templates/livekit/*
	fi
fi

# Config file for the dracut loader.
CONF="# AOSC OS LiveKit config for LiveKit loader.
# The LiveKit itself is the base layer.
# No more configuration required!
FSTYPE="$FSTYPE"
SYSROOT_DEP_base=('base')
"
info "Squashing rootfs ..."
packfs "$FSTYPE" "$OUT_PREFIX"/base."$FSTYPE" "$WORKDIR"/livekit

info "Installing GRUB config files ..."
make -C "$PWD"/boot/grub install TARGET=livekit

info "Writing config file ..."
echo "$CONF" > "$OUT_PREFIX"/livekit.conf

info "Copying hooks ..."
cp -a "$PWD"/hooks "$OUT_PREFIX"/

info "Done generating the LiveKit image!"
