#!/bin/bash
case "$ARCH" in
	amd64)
		MEMTEST_FILES=("memtest32" "memtest64")
		;;
	loongarch64)
		MEMTEST_FILES=("memtest64")
		;;
esac

if [ "$target" = installer ] ; then
	info "Creating configuration ..."
	# Remove livekit from SYSROOTS[@].
	# This is for the installer data.
	SYSROOT1=()
	# Remove base from SYSROOTS[@].
	# This is for the loader configuration.
	SYSROOT2=()
	for s in "${SYSROOTS[@]}" ; do
		if [ "$s" != "base" ] ; then
			SYSROOT2+=("$s")
		fi
		if [ "${s/livekit/}" == "$s" ] ; then
			SYSROOT1+=("$s")
		fi
	done
	echo "[installer]" >> "$ISODIR"/sysroots.ini
	echo "sysroots=${SYSROOT1[*]}" >> "$ISODIR"/sysroots.ini
	echo "LAYERS=$(dump_array OVERLAYS)" >> "$OUT_PREFIX"/livekit.conf
	echo "SYSROOT_LAYERS=$(dump_array SYSROOT2)" >> "$OUT_PREFIX"/livekit.conf
	cat "$TOP"/targets/installer.loader.conf.part2 >> "$OUT_PREFIX"/livekit.conf

	info "Generating recipe ..."
	"$TOP"/helpers/gen-recipe.py "$ISODIR"/sysroots.ini "$ISODIR"/manifest/recipe.json

	info "Generating recipe translations ..."
	"$TOP"/helpers/gen-i18n.py "$TOP"/helpers/recipe.ini "$TOP"/helpers/i18n gen-manifest
	cp -v "$TOP"/helpers/i18n/recipe-i18n.json "$ISODIR"/manifest/recipe-i18n.json
fi
# Install memtest86+ from the container
if [ "${ARCH/@(amd64|loongarch64)/}" != "$ARCH" ] ; then
	echo "Installing Memtest86+ binaries ..."
	for file in "${MEMTEST_FILES[@]}" ; do
		install -Dvm644 \
			"$WORKDIR"/base/boot/memtest86plus/"$file" \
			"$ISODIR"/boot/"$file"
	done
elif [ "$ARCH" = "loongson3" ] ; then
	echo "Installing PMON boot.cfg ..."
	install -vm644 "$PWD"/boot/boot-$target.cfg "$ISODIR"/boot/boot.cfg
fi
