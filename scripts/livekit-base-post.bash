#!/bin/bash
echo "Extracting LiveKit kernel/initramfs ..."
mkdir -pv "$ISODIR"/boot
cp -v "$WORKDIR"/base/kernel "$ISODIR"/boot/kernel
cp -v "$WORKDIR"/base/live-initramfs.img "$ISODIR"/boot/live-initramfs.img
rm -v "$WORKDIR"/base/kernel "$WORKDIR"/base/live-initramfs.img
if [ "$ARCH" = "loongson3" ] ; then
	cp -v "$WORKDIR"/base/live-initramfs-lite.img "$ISODIR"/boot/minird.img
	rm -v "$WORKDIR"/base/live-initramfs-lite.img
fi

if ! ab_match_archgroup retro ; then
	echo "Copying LiveKit template ..."
	chown -vR 0:0 templates/livekit/*
	cp -av templates/livekit/* $WORKDIR/base/
	chown -vR 1000:1001 $WORKDIR/base/home/live
	if [ "$SUDO_UID" != 0 ] ; then
		chown -vR $SUDO_UID:$SUDO_GID templates/livekit/*
	fi
fi
