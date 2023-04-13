#!/bin/bash
set -e
rm -fr livekit iso to-squash
mkdir iso to-squash

if [[ "${RETRO}" != "1" ]]; then
	echo "Generating LiveKit distribution ..."
	    aoscbootstrap \
        	stable livekit ${REPO:-https://repo.aosc.io/debs} \
	        --config /usr/share/aoscbootstrap/config/aosc-mainline.toml \
	        -x \
	        --arch ${ARCH:-$(dpkg --print-architecture)} \
	        -s /usr/share/aoscbootstrap/scripts/reset-repo.sh \
	        -s /usr/share/aoscbootstrap/scripts/enable-nvidia-drivers.sh \
	        -s /usr/share/aoscbootstrap/scripts/enable-dkms.sh \
	        -s "$PWD/scripts/livekit.sh" \
	        --include-files "$PWD/recipes/livekit.lst"
else
	echo "Generating Retro LiveKit distribution ..."
	    aoscbootstrap \
	        stable livekit ${REPO:-https://repo.aosc.io/debs-retro} \
	        --config /usr/share/aoscbootstrap/config/aosc-retro.toml \
	        -x \
	        --arch ${ARCH:-$(dpkg --print-architecture)} \
	        -s "$PWD/scripts/retro-livekit.sh" \
	        --include-files "$PWD/recipes/retro-livekit.lst"
fi

if [[ "${RETRO}" != "1" ]]; then
	echo "Copying LiveKit template ..."
	chown -vR 0:0 template/*
        cp -av template/* livekit/
	chown -vR 1000:1000 livekit/home/live
fi

echo "Extracting LiveKit kernel/initramfs ..."
mkdir -pv iso/boot
cp -v livekit/kernel iso/boot/kernel
cp -v livekit/live-initramfs.img iso/boot/live-initramfs.img

echo "Evaluating size of generated rootfs ..."
ROOTFS_SIZE="$(du -sm "livekit" | awk '{print $1}')"
ROOTFS_SIZE="$((ROOTFS_SIZE+ROOTFS_SIZE/2))"

echo "Generating empty back storage for rootfs ..."
mkdir -pv to-squash/LiveOS
truncate -s "${ROOTFS_SIZE}M" to-squash/LiveOS/rootfs.img

echo "Formatting rootfs ..."
mkfs.ext4 -F -m 1 to-squash/LiveOS/rootfs.img

echo "Filling rootfs ..."
mkdir mountpoint
mount -t ext4 -o loop to-squash/LiveOS/rootfs.img mountpoint/
rsync --info=progress2 -a livekit/* mountpoint/
umount mountpoint
rmdir mountpoint

echo "Generating squashfs for dracut dmsquash-live ..."
mkdir -pv iso/LiveOS
if [[ "${RETRO}" != "1" ]]; then
	env XZ_OPT="-9e --lzma2=preset=9e,dict=1536M,nice=273" \
	mksquashfs to-squash/ iso/LiveOS/squashfs.img \
		-comp xz -b 1M -Xdict-size 100% -no-recovery
else
        mksquashfs to-squash/ iso/LiveOS/squashfs.img \
                -comp lz4 -no-recovery
fi

echo "Copying boot template to ISO ..."
cp -av boot/* iso/

echo "Generating ISO with grub-mkrescue ..."
grub-mkrescue \
	-o aosc-os_livekit_$(date +%Y%m%d)_${ARCH:-$(dpkg --print-architecture)}.iso \
	iso -- -volid "LiveKit"

echo "Generating checksum ..."
sha256sum aosc-os_livekit_$(date +%Y%m%d)_${ARCH:-$(dpkg --print-architecture)}.iso \
	>> aosc-os_livekit_$(date +%Y%m%d)_${ARCH:-$(dpkg --print-architecture)}.iso.sha256sum

echo "Cleaning up ..."
rm -r iso to-squash livekit
