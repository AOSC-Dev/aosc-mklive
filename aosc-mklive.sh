set -e
mkdir iso to-squash
echo "Preparing OS with CIEL!..."
( yes yes | ciel farewell ) || true
ciel init
ciel load-os "$TARBALL"
if [ "$MIRROR" ]; then
	ciel switchmirror "$MIRROR"
fi
ciel update-os
ciel add ciel--livecd--
ciel shell -i ciel--livecd-- "apt-get update"
ciel shell -i ciel--livecd-- "apt-get install dracut -y"
if [ "$EXTRA_PACKAGES" ]; then
	ciel shell -i ciel--livecd-- "apt-get install $EXTRA_PACKAGES -y"
fi
if [ "$(ls ciel--livecd--/lib/modules/ | wc -l)" != "1" ]; then
	echo "Multiple or no kernel versions found, abort..." >&2
	( yes yes | ciel farewell ) || true
	rm -rfv iso to-squash
	exit 1
fi
KVER="$(ls ciel--livecd--/lib/modules/)"
KIMG=""
if [ -e "ciel--livecd--/boot/vmlinuz-$KVER" ]; then
	KIMG="ciel--livecd--/boot/vmlinuz-$KVER"
fi
if [ -e "ciel--livecd--/boot/vmlinux-$KVER" ]; then
	KIMG="ciel--livecd--/boot/vmlinux-$KVER"
fi
if [ ! "$KIMG" ]; then
	echo "Kernel image for $KVER not found, abort..." >&2
	( yes yes | ciel farewell ) || true
	rm -rfv iso to-squash
	exit 1
fi
echo "Extracting LiveCD kernel/initramfs before CIEL! instance is gone..."
ciel shell -i ciel--livecd-- "dracut --add \"dmsquash-live livenet\" \"/live-initramfs-$KVER.img\" $KVER"
mkdir -pv iso/boot
cp -v "$KIMG" iso/boot/kernel
cp -v "ciel--livecd--/live-initramfs-$KVER.img" iso/boot/live-initramfs.img
echo "Finalizing CIEL!..."
ciel factory-reset -i ciel--livecd--
ciel commit -i ciel--livecd--
ciel del ciel--livecd--
if [ "$MIRROR" ]; then
	ciel switchmirror origin
fi

echo "Evaulating size of generated rootfs..."
ROOTFS_SIZE="$(du -sm ".ciel/container/dist/" | awk '{print $1}')"
ROOTFS_SIZE="$((ROOTFS_SIZE+ROOTFS_SIZE/3))"

echo "Generating empty back storage for rootfs..."
mkdir -pv to-squash/LiveOS
truncate -s "${ROOTFS_SIZE}M" to-squash/LiveOS/rootfs.img

echo "Formatting rootfs..."
mkfs.ext4 -F -m 1 to-squash/LiveOS/rootfs.img

echo "Filling rootfs..."
mkdir mountpoint
mount -t ext4 -o loop to-squash/LiveOS/rootfs.img mountpoint/
rsync --info=progress2 -a .ciel/container/dist/* mountpoint/
umount mountpoint
rmdir mountpoint

echo "Generating squashfs for dracut dmsquash-live..."
mkdir -pv iso/LiveOS
mksquashfs to-squash/ iso/LiveOS/squashfs.img

echo "Copying template to ISO..."
DPKG_ARCH="$(dpkg-architecture -qDEB_BUILD_ARCH 2>/dev/null || true)"
cp -a template-noarch/* iso/
if [ -d "template-$DPKG_ARCH" ]; then
	cp -a template-$DPKG_ARCH/* iso/
fi

echo "Generating ISO with grub-mkrescue..."
grub-mkrescue -o live.iso iso -- -volid "AOSC_OS_LIVECD"

echo "Cleaning up..."
( yes yes | ciel farewell ) || true
rm -r iso to-squash
