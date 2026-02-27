CURNAME="$(basename $BASH_SOURCE)"
CURNAME="${CURNAME%%.*}"

case "$CURNAME" in
	desktop-nvidia)
		DRACUT_ADD_DRIVERS=" nvidia_drm "
		OUT_INITRD="live-initramfs-nvidia.img"
		;;
	desktop-nvidia-open)
		DRACUT_ADD_DRIVERS=" nvidia_drm "
		OUT_INITRD="live-initramfs-nvidia-open.img"
		;;
	desktop-cx4)
		DRACUT_ADD_DRIVERS=" cx4 "
		OUT_INITRD="live-initramfs-cx4.img"
		;;
	desktop-zhaoxin)
		DRACUT_ADD_DRIVERS=" zx_core zx "
		OUT_INITRD="live-initramfs-zhaoxin.img"
		;;
	desktop-loonggpu)
		DRACUT_ADD_DRIVERS=" loonggpu "
		OUT_INITRD="live-initramfs-loonggpu.img"
		;;
	desktop-arise)
		DRACUT_ADD_DRIVERS=" arise "
		OUT_INITRD="live-initramfs-arise.img"
		;;
	*)
		die "Invalid name linked to this script!"
		;;
esac

default_configuration() {
	case "$ARCH" in
		loongarch64)
			echo "16k"
			;;
		*)
			echo ""
			;;
	esac
}

echo "Installing plymouth-livekit ..."
echo "deb ${REPO} stable main" > "$TGT"/etc/apt/sources.list
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
	unset IFS
done
if [ -z "$kernel_selected" ] ; then
	echo "Internal error - no kernel selected to generate an initramfs image"
	exit 1
fi
systemd-nspawn -D "$TGT" -- dracut /"$OUT_INITRD" \
	--add "aosc-livekit-loader" \
	--omit "crypt mdraid lvm" \
	--no-hostonly \
	--no-hostonly-cmdline \
	--add-drivers "$DRACUT_ADD_DRIVERS" \
	"$kernel_selected"

install -Dvm644 "$TGT"/"$OUT_INITRD" "$OUTDIR"/boot/"$OUT_INITRD"
rm -v "$TGT"/"$OUT_INITRD"

echo "Cleaning up ..."
rm -r $TGT/var/cache/apt/archives
mkdir -pv $TGT/var/cache/apt/archives
rm -r $TGT/var/lib/oma/*
rm -r $TGT/var/lib/apt/lists/*
if [ -e $TGT/etc/machine-id ] ; then
	rm $TGT/etc/machine-id
	echo "uninitialized" > $TGT/etc/machine-id
fi
