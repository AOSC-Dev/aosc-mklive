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
	env REPO=$REPO TOPICS="$TOPICS" ${PWD}/gen-installer.sh || { echo "Failed to generate an installer image!" ; exit 1 ; }
	echo "Ditching unneeded desktop+nvidia template ..."
	rm -f "$PWD"/iso/squashfs/templates/desktop-nvidia.squashfs
}

call_gen_livekit() {
	echo "Calling gen-livekit.sh ..."
	env REPO=$REPO TOPICS="$TOPICS" ${PWD}/gen-livekit.sh || { echo "Failed to generate a LiveKit distribution!" ; exit 1 ; }
}

[ "x$EUID" = "x0" ] || { echo "Please run me as root." ; exit 1 ; }

export ARCH="${ARCH:-$(dpkg --print-architecture)}"

tgt=$1
case "$tgt" in
	livekit)
		call_gen_livekit
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
	wget https://www.memtest.org/download/v${MT86VER:-7.00}/mt86plus_${MT86VER:-7.00}.src.zip
	unzip mt86plus_${MT86VER:-7.00}.src.zip

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

if [[ "$ARCH" = "amd64" || \
      "$ARCH" = "arm64" || \
      "$ARCH" = "loongarch64" ]]; then
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
	fi
	files_to_extract=("boot/grub" "EFI" ".disk")
	if [[ "$ARCH" = "amd64" ]]; then
		files_to_extract+=("System" "mach_kernel")
	fi
	xorriso -osirrox on -indev "$ISO_NAME" -extract_l / iso/ "${files_to_extract[@]}" --
	if [[ "$have_sb" = "1" ]]; then
		mkdir -p sb
		wget -O sb/grub.deb "https://deb.debian.org/debian/pool/main/g/grub-efi-${ARCH}-signed/grub-efi-${ARCH}-signed_1%2B2.06%2B13%2Bdeb12u1_${ARCH}.deb"
		wget -O sb/shim.deb "https://deb.debian.org/debian/pool/main/s/shim-signed/shim-signed_1.44~1+deb12u1+15.8-1~deb12u1_${ARCH}.deb"
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
EOF
	fi
	if [[ "$ARCH" = "loongarch64" ]]; then
		# Some old-world firmware only recognizes BOOTLOONGARCH.EFI.
		cp iso/EFI/BOOT/BOOTLOONGARCH64.EFI \
			iso/EFI/BOOT/BOOTLOONGARCH.EFI
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
	> "$ISO_NAME".sha256sum

if [ "x$SUDO_UID" != "x" ] && [ "x$SUDO_GID" != "x" ] ; then
       echo "Changing owner of generated iso ..."
       chown -v "$SUDO_UID:$SUDO_GID" $ISO_NAME $ISO_NAME.sha256sum
fi

echo "Cleaning up ..."
rm -fr iso to-squash livekit memtest sb
