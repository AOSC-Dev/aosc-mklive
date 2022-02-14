echo "Generating a LiveKit initramfs ..."
dracut \
    --add "dmsquash-live drm" --omit "network dbus-daemon dbus network-manager btrfs crypt kernel-modules-extra kernel-network-modules multipath mdraid nvdimm nvmf lvm" \
    --xz --no-early-microcode \
    "/live-initramfs.img" \
    $(ls /usr/lib/modules/)

echo "Moving kernel image out ..."
if [ ! -h /boot/vmlinuz-* ]; then
    mv -v /boot/vmlinuz-* /kernel
elif [ ! -h /boot/vmlinux-* ]; then
    mv -v /boot/vmlinux-* /kernel
else
    echo "No kernel installed, aborting ..."
fi

echo "Enabling KMSCON with auto-login ..."
rm -fv /etc/systemd/system/getty.target.wants/getty@tty1.service
ln -sfv ../../../usr/lib/systemd/system/kmsconvt@.service /etc/systemd/system/autovt@.service
mkdir -pv /etc/systemd/system/kmsconvt@.service.d/
cat > /etc/systemd/system/kmsconvt@.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/kmscon "--vt=%I" --seats=seat0 --no-switchvt --login -- /usr/bin/login -f root
EOF

echo "Cutting out unwanted files ..."
rm -rf /usr/{include,src,share/{doc,gtk-doc}}
rm `find /usr/lib -name '*.a'`

echo "Setting up autologin with LightDM ..."
sed -i -e 's/\#autologin-user=/autologin-user=root/g' \
       -e 's/\#autologin-session=/autologin-session=mate/g' \
       /etc/lightdm/lightdm.conf
ln -sfv ../../../usr/lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
