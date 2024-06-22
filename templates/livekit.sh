#!/bin/bash

echo "Copying kernel and initramfs ..."
cp "$WORKDIR"/livekit/kernel "$OUTDIR"/
cp "$WORKDIR"/livekit/live-initramfs.img "$OUTDIR"/
rm -v "$WORKDIR"/livekit/kernel
rm -v "$WORKDIR"/livekit/live-initramfs.img
