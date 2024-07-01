#!/bin/bash
set -e

usage() {
	cat << EOF
Usage: $0 livekit|installer

Positional arguments:
	livekit		Generate an AOSC OS LiveKit image.
	installer	Generate an AOSC OS offline installer image.

Environment variables:
	REPO	URL to the AOSC OS package repository.
	BRANCH	Which topic to install.
	RETRO	Whether to generate a Retro LiveKit.
EOF
}

call_gen_installer() {
	echo "Calling gen-installer.sh ..."
	env REPO=$REPO ${PWD}/gen-installer.sh || { echo "Failed to generate an installer image!" ; exit 1 ; }
}

[ "x$EUID" = "x0" ] || { echo "Please run me as root." ; exit 1 ; }

export ARCH="${ARCH:-$(dpkg --print-architecture)}"

gen_livekit() {
	rm -fr livekit iso to-squash memtest sb
	mkdir iso to-squash	
	
	if [[ "${ARCH}" = "loongarch64" ]]; then
		echo "Generating LiveKit distribution (loongarch64) ..."
		aoscbootstrap \
			${BRANCH:-stable} livekit ${REPO:-https://repo.aosc.io/debs} \
			--config /usr/share/aoscbootstrap/config/aosc-mainline.toml \
			-x \
			--arch ${ARCH:-$(dpkg --print-architecture)} \
			-s /usr/share/aoscbootstrap/scripts/reset-repo.sh \
			-s /usr/share/aoscbootstrap/scripts/enable-nvidia-drivers.sh \
			-s /usr/share/aoscbootstrap/scripts/enable-dkms.sh \
			-s "$PWD/scripts/livekit.sh" \
			-s "$PWD/scripts/loongarch64-tweaks.sh" \
			--include-files "$PWD/recipes/livekit.lst"
	elif [[ "${RETRO}" != "1" ]]; then
		echo "Generating LiveKit distribution ..."
		aoscbootstrap \
			${BRANCH:-stable} livekit ${REPO:-https://repo.aosc.io/debs} \
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
		        ${BRANCH:-stable} livekit ${REPO:-https://repo.aosc.io/debs-retro} \
		        --config /usr/share/aoscbootstrap/config/aosc-retro.toml \
		        -x \
		        --arch ${ARCH:-$(dpkg --print-architecture)} \
		        -s "$PWD/scripts/retro-livekit.sh" \
		        --include-files "$PWD/recipes/retro-livekit.lst"
	fi
	
	if [[ "${RETRO}" != "1" ]]; then
		echo "Copying LiveKit template ..."
		chown -vR 0:0 templates/livekit/*
	        cp -av templates/livekit/* livekit/
		chown -vR 1000:1001 livekit/home/live
	fi
	
	echo "Extracting LiveKit kernel/initramfs ..."
	mkdir -pv iso/boot
	cp -v livekit/kernel iso/boot/kernel
	cp -v livekit/live-initramfs.img iso/boot/live-initramfs.img
	rm -v livekit/kernel livekit/live-initramfs.img
	
	echo "Evaluating size of generated rootfs ..."
	ROOTFS_SIZE="$(du -sm "livekit" | awk '{print $1}')"
	ROOTFS_SIZE="$((ROOTFS_SIZE+ROOTFS_SIZE/2))"
	
	echo "Generating empty back storage for rootfs ..."
	mkdir -pv to-squash/LiveOS
	truncate -s "${ROOTFS_SIZE}M" to-squash/LiveOS/rootfs.img
	
	echo "Formatting rootfs ..."
	mkfs.ext4 -F -m 1 -d livekit/ to-squash/LiveOS/rootfs.img
	
	echo "Generating squashfs for dracut dmsquash-live ..."
	mkdir -pv iso/LiveOS
	mksquashfs to-squash/ iso/LiveOS/squashfs.img \
	    -comp lz4 -no-recovery
	
	echo "Copying boot template to ISO ..."
	cp -av boot iso/
	
	if [[ "${ARCH}" = "loongarch64" ]]; then
		echo "Adding an option to use discrete graphics (bypassing AST) ..."
		sed \
			-e 's|la64_quirk=0|la64_quirk=1|g' \
			-i iso/boot/grub/grub.cfg
	fi
	
	if [[ "$RETRO" = "1" ]]; then
		echo "Tweaking GRUB menu to disable gfxterm, change color ..."
		sed \
			-e 's|retro=0|retro=1|g' \
			-i iso/boot/grub/grub.cfg
	fi
}

tgt=$1
case "$tgt" in
	livekit)
		gen_livekit
		ISO_NAME="aosc-os_livekit_$(date +%Y%m%d)${REV:+.$REV}_${ARCH}.iso"
		;;
	installer)
		call_gen_installer
		ISO_NAME="aosc-os_installer_$(date +%Y%m%d)${REV:+.$REV}_${ARCH}.iso"
		;;
	*)
		usage
		exit 1
		;;
esac

if [[ "${ARCH}" = "amd64" || \
      "${ARCH}" = "i486" ]]; then
	echo "Building and installing Memtest86+ ..."
	mkdir memtest && cd memtest
	wget https://www.memtest.org/download/v${MT86VER:-6.20}/mt86plus_${MT86VER:-6.20}.src.zip
	unzip mt86plus_${MT86VER:-6.20}.src.zip

	if [[ "${ARCH}" = "amd64" ]]; then
		make -C build64
		install -Dvm644 build64/memtest.{bin,efi} \
			../iso/boot/
	elif [[ "${ARCH}" = "i486" ]]; then
		sed -e 's|i586|i486|g' \
			-i build32/Makefile
		make -C build32 \
			CC="gcc-multilib-wrapper"
		install -Dvm644 build32/memtest.{bin,efi} \
			../iso/boot/
	fi
	cd ..
fi

echo "Generating ISO with grub-mkrescue ..."
grub-mkrescue \
	-o "$ISO_NAME" \
	iso -- -volid "LiveKit"

if [[ "$ARCH" = "amd64" || "$ARCH" = "arm64" ]]; then
	# Handle Secure Boot: Add a warning for unsupported feature.
	arch_suffix=""
	arch_suffix_upper=""
	have_sb=0
	if [[ "$ARCH" = "amd64" ]]; then
		arch_suffix="x64"
		arch_suffix_upper="x64"
		have_sb="1"
	elif [[ "$ARCH" = "arm64" ]]; then
		arch_suffix="aa64"
		arch_suffix_upper="AA64"
		have_sb="1"
	else
		arch_suffix="loongarch64"
		arch_suffix_upper="LOONGARCH64"
	fi
	files_to_extract=("boot/grub" "EFI" ".disk")
	if [[ "$ARCH" = "amd64" ]]; then
		files_to_extract+=("System" "mach_kernel")
	fi
	xorriso -osirrox on -indev "$ISO_NAME" -extract_l / iso/ "${files_to_extract[@]}" --
	if [[ "$have_sb" = "1" ]]; then
		mkdir -p sb
		wget -O sb/grub.deb "https://deb.debian.org/debian/pool/main/g/grub-efi-${ARCH}-signed/grub-efi-${ARCH}-signed_1%2B2.06%2B13%2Bdeb12u1_${ARCH}.deb"
		wget -O sb/shim.deb "https://deb.debian.org/debian/pool/main/s/shim-signed/shim-signed_1.39%2B15.7-1_${ARCH}.deb"
		dpkg-deb -x sb/grub.deb sb
		dpkg-deb -x sb/shim.deb sb
		mv "iso/EFI/BOOT/BOOT${arch_suffix_upper}.EFI" "iso/EFI/BOOT/grub${arch_suffix}.efi"
		mv "sb/usr/lib/shim/shim${arch_suffix}.efi.signed" "iso/EFI/BOOT/BOOT${arch_suffix_upper}.EFI"
		mv "sb/usr/lib/grub/"*"-efi-signed/grub${arch_suffix}.efi.signed" "iso/EFI/BOOT/mm${arch_suffix}.efi"
		mkdir -p "iso/EFI/debian"
		cat > iso/EFI/debian/grub.cfg <<EOF
loadfont unicode
menuentry 'Secure Boot is enabled and NOT supported!' {
	true
}
menuentry 'UEFI Firmware Settings' {
	fwsetup
}
menuentry 'Boot Default OS' {
	exit 1
}
fi
EOF
	fi
	# 32.5MiB
	mformat -C -F -i "iso/efi.img" -T 66650 -h 2 -s 32 -c 1 -F "::"
	mcopy -i "iso/efi.img" -s "iso/EFI" "::/"
	timestamp=$(basename iso/.disk/*.uuid | cut -d "." -f 1 | tr -d '-')
	rm -f "$ISO_NAME"
	additional_opts=()
	if [[ "$ARCH" = "amd64" ]]; then
		additional_opts+=(-b "boot/grub/i386-pc/eltorito.img" -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info --grub2-mbr "/usr/lib/grub/i386-pc/boot_hybrid.img" -hfsplus -apm-block-size 2048 -hfsplus-file-creator-type chrp tbxj "/System/Library/CoreServices/.disk_label" -hfs-bless-by i "/System/Library/CoreServices/boot.efi")
	fi
	xorriso -as mkisofs -graft-points --modification-date="$timestamp" "${additional_opts[@]}" --iso-level 3 --efi-boot efi.img -efi-boot-part --efi-boot-image --protective-msdos-label -o "$ISO_NAME" --sort-weight 0 / --sort-weight 1 /boot iso --  -volid "LiveKit"
fi

echo "Generating checksum ..."
sha256sum "$ISO_NAME" \
	>> "$ISO_NAME".sha256sum

if [ "x$SUDO_UID" != "x" ] && [ "x$SUDO_GID" != "x" ] ; then
       echo "Changing owner of generated iso ..."
       chown -v "$SUDO_UID:$SUDO_GID" $ISO_NAME $ISO_NAME.sha256sum
fi

echo "Cleaning up ..."
rm -fr to-squash livekit memtest sb
