#!/bin/bash

echo "Copying kernel and initramfs ..."
mkdir -p "$OUTDIR"/boot
cp "$WORKDIR"/livekit/kernel "$OUTDIR"/boot/
cp "$WORKDIR"/livekit/live-initramfs.img "$OUTDIR"/boot/
rm -v "$WORKDIR"/livekit/kernel
rm -v "$WORKDIR"/livekit/live-initramfs.img
