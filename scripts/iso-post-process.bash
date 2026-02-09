#!/bin/bash

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
	xorriso -osirrox on -indev "$OUTPUT" -extract_l / "$ISODIR"/ "${files_to_extract[@]}" --
	if [[ "$have_sb" = "1" ]]; then
		mkdir -p $WORKDIR/sb
		wget -O $WORKDIR/sb/grub.deb "https://deb.debian.org/debian/pool/main/g/grub-efi-${ARCH}-signed/grub-efi-${ARCH}-signed_1+2.12+9_${ARCH}.deb"
		wget -O $WORKDIR/sb/shim.deb "https://deb.debian.org/debian/pool/main/s/shim-signed/shim-signed_1.47+15.8-1_${ARCH}.deb"
		dpkg-deb -x $WORKDIR/sb/grub.deb $WORKDIR/sb
		dpkg-deb -x $WORKDIR/sb/shim.deb $WORKDIR/sb
		mv ""$ISODIR"/EFI/BOOT/BOOT${arch_suffix_upper}.EFI" ""$ISODIR"/EFI/BOOT/grub${arch_suffix}.efi"
		mv "$WORKDIR/sb/usr/lib/shim/shim${arch_suffix}.efi.signed" ""$ISODIR"/EFI/BOOT/BOOT${arch_suffix_upper}.EFI"
		mv "$WORKDIR/sb/usr/lib/grub/"*"-efi-signed/grub${arch_suffix}.efi.signed" ""$ISODIR"/EFI/BOOT/mm${arch_suffix}.efi"
		mkdir -p ""$ISODIR"/EFI/debian"
		cat > "$ISODIR"/EFI/debian/grub.cfg <<EOF
loadfont unicode
menuentry 'Sorry, AOSC OS does not support Secure Boot.' {
	true
}
menuentry 'Please disable Secure Boot before continuing.' {
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
		cp "$ISODIR"/EFI/BOOT/BOOTLOONGARCH64.EFI \
			"$ISODIR"/EFI/BOOT/BOOTLOONGARCH.EFI
	fi
	# 32.5MiB
	mformat -C -F -i ""$ISODIR"/efi.img" -T 66650 -h 2 -s 32 -c 1 -F "::"
	mcopy -i ""$ISODIR"/efi.img" -s ""$ISODIR"/EFI" "::/"
	timestamp=$(basename "$ISODIR"/.disk/*.uuid | cut -d "." -f 1 | tr -d '-')
	rm -f "$OUTPUT"
	additional_opts=()
	if [[ "$ARCH" = "amd64" ]]; then
		additional_opts+=(-b "boot/grub/i386-pc/eltorito.img" -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info --grub2-mbr "/usr/lib/grub/i386-pc/boot_hybrid.img" -hfsplus -apm-block-size 2048 -hfsplus-file-creator-type chrp tbxj "/System/Library/CoreServices/.disk_label" -hfs-bless-by i "/System/Library/CoreServices/boot.efi")
	fi
	xorriso -as mkisofs -graft-points --modification-date="$timestamp" "${additional_opts[@]}" --iso-level 3 --efi-boot efi.img -efi-boot-part --efi-boot-image --protective-msdos-label -o "$OUTPUT" --sort-weight 0 / --sort-weight 1 /boot "$ISODIR" --  -volid "$VOLID"
fi
