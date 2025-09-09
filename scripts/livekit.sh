MANUALS_TO_STRIP=(
	"/usr/share/man/man3"
	"/usr/share/man/man3l"
)

default_config() {
	case "$(uname -m)" in
		loongarch64)
			echo "16k"
			;;
		*)
			;;
	esac
}

echo "Customising Plymouth theme ..."
sed -e 's|semaphore|livekit|g' \
    -i /etc/plymouth/plymouthd.conf

echo "Generating a LiveKit initramfs ..."
IFS=$'\n'
KERNELS=($(ls /usr/lib/modules/))
unset IFS
for kernel in "${KERNELS[@]}" ; do
	IFS='-'
	components=($kernel)
	unset IFS
	kernel_config="${components[3]}"
	if [ -n "$kernel_config" ] ; then
		if [ "$(default_config)" = "$kernel_config" ] ; then
			kernel_selected="$kernel"
			break
		fi
	else
		kernel_selected="$kernel"
		break
	fi
done
if [ -z "$kernel_selected" ] ; then
	echo "Internal error - no kernel selected to generate a initramfs image"
	exit 1
fi
echo "Generating initramfs image using kernel $kernel_selected ..."
if [ "x$INSTALLER" != "x1" ] ; then
	tmpdir=$(mktemp -d)
	pushd $tmpdir
		tar xf /dracut.tar
		rm /dracut.tar
		cp -av dracut/90aosc-livekit-loader /usr/lib/dracut/modules.d/
	popd
	rm -r $tmpdir
	# Host-only mode should be disabled. This initramfs is generic.
	dracut \
		--xz -c /dev/zero \
		--add "aosc-livekit-loader drm" \
		--omit "crypt mdraid lvm" \
		--no-hostonly \
		--xz --no-early-microcode \
		/live-initramfs.img \
		"$kernel_selected"
else
	cp -av /run/mklive/dracut/90aosc-livekit-loader /usr/lib/dracut/modules.d/
	dracut \
		--xz -c /dev/zero \
		--add "aosc-livekit-loader drm" \
		--omit "crypt mdraid lvm" \
		--no-hostonly \
		--xz --no-early-microcode \
		--omit "crypt mdraid lvm" \
		/live-initramfs.img \
		"$kernel_selected"
fi

if [ "$(dpkg --print-architecture)" = "loongson3" ] ; then
	# Generate a stripped-down version of the initrd, specifically for
	# PMON, because:
	# 1. It is VERY slow for PMON to load a file into the memory from
	#    USB. A 7MiB kernel takes thirty seconds!
	# 2. Some PMON implementations does not support long file names in
	#    ISO9660 - PMON will report ENOENT if one tries to load them.
	# 3. Furthermore, we might have to embed an ext2 partition just to
	#    cope with some other limitations of some weird PMON impls.
	echo "Generating a stripped-down initramfs for PMON ..."
	dracut \
		--xz \
		-c /dev/zero \
		--add "drm dm aosc-livekit-loader" \
		--xz --no-early-microcode \
		--omit "network i18n plymouth crypt mdraid lvm ostree qemu virtiofs bcache btreefs kernel-modules-extra hwdb lunmask btrfs modsign dm systemd-battery-check qemu-net resume  " \
		"/live-initramfs-lite.img" --force
fi

echo "Moving kernel image out ..."
for f in "vmlinuz-$kernel_selected" "vmlinux-$kernel_selected" ; do
	if [  -e /boot/"$f" ] ; then
		mv -v /boot/$f /kernel
		break
	fi
done
if [ ! -e /kernel ] ; then
	echo "Internal error - /kernel does not exist"
	exit 1
fi

echo "Cleaning up unused kernel files ..."
for kernel in "${KERNELS[@]}" ; do
	if [ "$kernel" = "$kernel_selected" ] ; then
		continue
	fi
	for f in "vmlinuz-$kernel" "vmlinux-$kernel" ; do
		if [ -e /boot/"$f" ] ; then
			rm -v /boot/$f
		fi
	done
	rm -rvf /lib/modules/"$kernel"
	rm -rvf /usr/src/linux-headers-"$kernel" || true
done

echo "Enabling KMSCON with auto-login ..."
rm -fv /etc/systemd/system/getty.target.wants/getty@tty1.service
mkdir -pv /usr/lib/systemd/system/getty.target.wants/
ln -sfv ../kmsconvt@.service /usr/lib/systemd/system/getty.target.wants/kmsconvt@tty1.service
ln -sfv kmsconvt@.service /usr/lib/systemd/system/autovt@.service
mkdir -pv /usr/lib/systemd/system/kmsconvt@.service.d/
cat > /usr/lib/systemd/system/kmsconvt@.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/kmscon "--vt=%I" --seats=seat0 --no-switchvt --login -- /usr/bin/login -f root
EOF

echo "Cutting out unwanted files ..."
if [ "x$INSTALLER" != "x1" ] ; then
	rm -rf /usr/{include,src,share/{clc,doc,gir-1.0,gtk-doc,ri}}
	rm `find /usr/lib -name '*.a'`
else
	rm -rf /usr/share/{clc,doc,gir-1.0,gtk-doc,ri}
	rm `find /usr/lib -name '*.a'`
fi

if [ "x$INSTALLER" = "x1" ] ; then
	echo "Adding a user for NVIDIA ..."
	groupadd -g 143 nvidia-persistenced
	useradd -c 'NVIDIA Persistence Daemon' -u 143 -g nvidia-persistenced -d '/' -s /sbin/nologin nvidia-persistenced
fi

echo "Creating a default live user ..."
useradd live -m
usermod -a -G audio,cdrom,video,wheel live

echo "Preparing for sysinstall ..."
groupadd -r sysinstall
usermod -a -G sysinstall live

echo "Preparing for autologin ..."
groupadd -r autologin
usermod -a -G autologin live

echo "Disabling suspend and hibernation ..."
systemctl mask suspend.target
systemctl mask hibernation.target

echo "Disabling open file handle limit ..."
sed -e '/^fs.file-max/d' \
    -i /etc/sysctl.d/00-kernel.conf

echo "Removing unnecessary manual pages..."
for mandir in ${MANUALS_TO_STRIP[@]} ; do
	echo "Removing $mandir"
	rm -r $mandir
done

echo "Removing unnecessary services ..."
rm -v \
	/etc/xdg/autostart/user-dirs-update-gtk.desktop \
	/etc/xdg/autostart/xdg-user-dirs.desktop \
	/usr/lib/systemd/system/lightdm.service

echo "Enabling DeployKit backend service ..."
ln -sfv ../deploykit-backend.service \
	/usr/lib/systemd/system/multi-user.target.wants/deploykit-backend.service

echo "Enabling pre-desktop DeployKit GUI service ..."
mkdir -pv /usr/lib/systemd/system/display-manager.service.wants
ln -sfv ../deploykit-gui.service \
	/usr/lib/systemd/system/display-manager.service.wants/deploykit-gui.service

echo "Removing a problematic library ..."
# FIXME: Causes crashes on unaccelerated platforms (i.e. VMs).
rm -v /usr/lib/gstreamer-1.0/libgstvaapi.so

echo "Removing unused CJK fonts ..."
rm -v \
	/usr/share/fonts/TTF/NotoSerif* \
	/usr/share/fonts/OTF/NotoSansMonoCJK*

echo "Allowing any user to run localectl ..."
sed \
	-e 's|auth_admin_keep|yes|g' \
	-i /usr/share/polkit-1/actions/org.freedesktop.locale1.policy

echo "Making way for a dkcli warpper ..."
mv -v /usr/bin/dkcli{,.bin}
