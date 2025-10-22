default_config() {
	# Stub - loongarch64 does not have NVIDIA drivers, and there's no
	# other kernel configurations for arm64.
	echo ""
}

echo "Installing plymouth-livekit ..."
systemd-nspawn -D $TGT -- \
	oma --no-check-dbus install \
	--yes --no-refresh-topics plymouth-livekit

echo "Customising Plymouth theme ..."
sed -e 's|semaphore|livekit|g' \
    -i $TGT/etc/plymouth/plymouthd.conf

echo "Generating a LiveKit initramfs image with NVIDIA driver ..."
cp -a ${TOP}/dracut/90aosc-livekit-loader \
	$TGT/usr/lib/dracut/modules.d/
IFS=$'\n'
KERNELS=($(ls $TGT/usr/lib/modules/))
unset IFS
for kernel in "${KERNELS[@]}" ; do
	IFS='-'
	# NOTE: do NOT add quotes around this, otherwise the version string
	# won't be sliced.
	components=($kernel)
	kernel_configuration="${components[3]}"
	if [ -n "$kernel_configuration" ] ; then
		if [ "$(default_configuration)" = "$kernel_configuration" ] ; then
			kernel_selected="$kernel"
		fi
	else
		kernel_selected="$kernel"
	fi
done
if [ -z "$kernel_selected" ] ; then
	echo "Internal error - no kernel selected to generate an initramfs image"
	exit 1
fi
systemd-nspawn -D "$TGT" -- dracut /live-initramfs-nvidia.img \
	--add "aosc-livekit-loader" \
	--omit "crypt mdraid lvm" \
	--no-hostonly \
	--add-drivers "nvidia nvidia-modeset nvidia-uvm nvidia-drm" \
	"$kernel_selected"

install -Dvm644 "$TGT"/live-initramfs-nvidia.img "$OUTDIR"/boot/live-initramfs-nvidia.img
rm -v "$TGT"/live-initramfs-nvidia.img

echo "Cleaning up ..."
rm -r $TGT/var/cache/apt/archives
mkdir -pv $TGT/var/cache/apt/archives
rm -r $TGT/var/lib/oma/*
rm -r $TGT/var/lib/apt/lists/*
if [ -e $TGT/etc/machine-id ] ; then
	rm $TGT/etc/machine-id
	echo "uninitialized" > $TGT/etc/machine-id
fi
