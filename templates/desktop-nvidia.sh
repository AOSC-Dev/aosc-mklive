echo "Installing plymouth-livekit ..."
systemd-nspawn -D $TGT -- oma --no-check-dbus install --yes plymouth-livekit

echo "Customising Plymouth theme ..."
sed -e 's|semaphore|livekit|g' \
    -i $TGT/etc/plymouth/plymouthd.conf

echo "Generating a LiveKit initramfs image with NVIDIA driver ..."
cp -a ${TOP}/dracut/90aosc-livekit-loader \
	$TGT/usr/lib/dracut/modules.d/
systemd-nspawn -D $TGT -- dracut /live-initramfs-nvidia.img \
	--add "aosc-livekit-loader" \
	--omit "crypt mdraid lvm" \
	--add-drivers "nvidia nvidia-modeset nvidia-uvm nvidia-drm" \
	$(ls $TGT/usr/lib/modules/)
install -Dvm644 $TGT/live-initramfs-nvidia.img $OUTDIR/boot/live-initramfs-nvidia.img
rm -v $TGT/live-initramfs-nvidia.img
