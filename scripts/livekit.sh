MANUALS_TO_STRIP=(
	"/usr/share/man/man3"
	"/usr/share/man/man3l"
)

echo "Customising Plymouth theme ..."
sed -e 's|semaphore|livekit|g' \
    -i /etc/plymouth/plymouthd.conf

echo "Generating a LiveKit initramfs ..."
if [ "x$INSTALLER" != "x1" ] ; then
	dracut \
		--add "dmsquash-live drm" --omit "network dbus-daemon dbus network-manager btrfs crypt kernel-modules-extra kernel-network-modules multipath mdraid nvdimm nvmf lvm" \
		--xz --no-early-microcode \
		"/live-initramfs.img" \
		$(ls /usr/lib/modules/)
else
	cp -av /run/mklive/dracut/90aosc-livekit-loader /usr/lib/dracut/modules.d/
	dracut \
		--add "aosc-livekit-loader drm" \
		--xz --no-early-microcode \
		"/live-initramfs.img" \
		$(ls /usr/lib/modules/)
fi

echo "Moving kernel image out ..."
if [ -f /boot/vmlinuz-* ]; then
    mv -v /boot/vmlinuz-* /kernel
elif [ -f /boot/vmlinux-* ]; then
    mv -v /boot/vmlinux-* /kernel
else
    echo "No kernel installed, aborting ..."
fi

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
rm -rf /usr/{include,src,share/{clc,doc,gir-1.0,gtk-doc,ri}}
rm `find /usr/lib -name '*.a'`

echo "Generating /etc/motd ..."
cat > /etc/motd << EOF
Welcome to AOSC OS LiveKit!

Here you may find basic tools to install AOSC OS, or rescue other operating
systems installed on your computer. Here below is a basic guide to preinstalled
applications (in the form of commands) on LiveKit:

- deploykit: AOSC OS installer.
- cfdisk: Disk partition manager.
- nmtui: Network (Ethernet, Wi-Fi, etc.) connection manager.
- w3m: Web browser.

If you have encountered any issue, please get in touch with us:

- IRC: #aosc on Libera.Chat
- GitHub: https://github.com/AOSC-Dev/aosc-os-abbs/issues/new/

Enjoy your stay!

EOF

echo "Creating a default live user ..."
useradd live -m
echo live:live | chpasswd
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
