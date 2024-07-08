#!/bin/bash

# FIXME GStreamer refused to load its modules because a bunch of symbol
# lookup errors, even their dependencies and shared symbols does exist.
# Reinstalling GStreamer does fix this problem, so we do it here.
echo "Reinstalling gstreamer ..."
pushd $TGT
apt update
apt download gstreamer
systemd-nspawn -D $TGT apt install --reinstall /$(basename $(ls $TGT/gstreamer_*.deb))
rm -r $TGT/var/cache/apt/archives/*
rm $TGT/usr/lib/gstreamer-1.0/libgstvaapi.so
popd

echo "Copying kernel and initramfs ..."
mkdir -p "$OUTDIR"/boot
cp "$WORKDIR"/livekit/kernel "$OUTDIR"/boot/
cp "$WORKDIR"/livekit/live-initramfs.img "$OUTDIR"/boot/
rm -v "$WORKDIR"/livekit/kernel
rm -v "$WORKDIR"/livekit/live-initramfs.img
