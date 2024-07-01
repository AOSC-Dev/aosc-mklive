#!/bin/bash

echo "Generating LiveKit initramfs image with NVIDIA added ..."
systemd-nspawn -D "$TGT" -- dracut /live-initramfs-nvidia.img --add "aosc-livekit-loader" --add-drivers "nvidia nvidia-modeset nvidia-uvm nvidia-drm"

echo "Copying kernel and initramfs ..."
cp "$TGT"/live-initramfs-nvidia.img "$OUTDIR"/boot/
rm -v "$TGT"/live-initramfs-nvidia.img
