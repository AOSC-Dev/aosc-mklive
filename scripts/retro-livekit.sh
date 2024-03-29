MANUALS_TO_STRIP=(
	"/usr/share/man"
)

echo "Generating a LiveKit initramfs ..."
dracut \
    --add "dmsquash-live drm" --omit "network dbus-daemon dbus network-manager btrfs crypt kernel-modules-extra kernel-network-modules multipath mdraid nvdimm nvmf lvm" \
    --xz --no-early-microcode \
    "/live-initramfs.img" \
    $(ls /usr/lib/modules/)

echo "Moving kernel image out ..."
if [ -f /boot/vmlinuz-* ]; then
    mv -v /boot/vmlinuz-* /kernel
elif [ -f /boot/vmlinux-* ]; then
    mv -v /boot/vmlinux-* /kernel
else
    echo "No kernel installed, aborting ..."
fi

echo "Enabling auto-login ..."
mkdir -pv /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
EOF

echo "Cutting out unwanted files ..."
rm -rf /usr/{include,src,share/{doc,gtk-doc}}
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

echo "Removing unnecessary manual pages..."
for mandir in ${MANUALS_TO_STRIP[@]} ; do
        echo "Removing $mandir"
        rm -rf $mandir
done
