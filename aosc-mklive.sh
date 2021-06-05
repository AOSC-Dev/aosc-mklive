set -e
rm -r iso to-squash
mkdir iso to-squash

echo "Generating LiveKit distribution ..."
aoscbootstrap \
    stable livekit ${REPO:-https://repo.aosc.io/debs} \
    --config /usr/share/aoscbootstrap/config/aosc-mainline.toml \
    -x \
    --arch ${ARCH:-$(dpkg --print-architecture)} \
    -s \
        /usr/share/aoscbootstrap/scripts/reset-repo.sh \
        /usr/share/aoscbootstrap/scripts/enable-nvidia-drivers.sh \
        /usr/share/aoscbootstrap/scripts/enable-dkms.sh \
        /usr/share/aoscbootstrap/scripts/livekit.sh \
    --include-files /usr/share/aoscbootstrap/recipes/livekit.lst

echo "Extracting LiveKit kernel/initramfs ..."
mkdir -pv iso/boot
cp -v livekit/kernel iso/boot/kernel
cp -v livekit/live-initramfs.img iso/boot/live-initramfs.img

echo "Evaulating size of generated rootfs..."
ROOTFS_SIZE="$(du -sm "livekit" | awk '{print $1}')"
ROOTFS_SIZE="$((ROOTFS_SIZE+ROOTFS_SIZE/3))"

echo "Generating empty back storage for rootfs..."
mkdir -pv to-squash/LiveOS
truncate -s "${ROOTFS_SIZE}M" to-squash/LiveOS/rootfs.img

echo "Formatting rootfs..."
mkfs.ext4 -F -m 1 to-squash/LiveOS/rootfs.img

echo "Filling rootfs..."
mkdir mountpoint
mount -t ext4 -o loop to-squash/LiveOS/rootfs.img mountpoint/
rsync --info=progress2 -a livekit/* mountpoint/
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
rm -r iso to-squash
