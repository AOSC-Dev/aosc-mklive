[[ -d "$TGT" ]] || { echo "TGT is not set." ; exit 1 ; }

echo "Removing problematic files ..."
rm $TGT/usr/lib/gstreamer-1.0/libgstvaapi.so

echo "Creating a live user ... "
useradd -R $TGT -m -s /bin/bash live
usermod -R $TGT -aG audio,video,plugdev,tty,wheel live
chfn -R $TGT -f "Live session user"

echo "Copying user skeletons ..."
for file in $(ls -A ${WORKDIR}/merged/etc/skel/) ; do
	cp -a $TGT/etc/skel/$file $TGT/home/live/
	chown -R 1000:1000 $TGT/home/live/$file
done

echo "Bypassing sudo password ..."
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > $TGT/etc/sudoers.d/livekit

echo "Disabling suspend and hibernation ..."
systemd-nspawn -D $TGT systemctl mask suspend.target
systemd-nspawn -D $TGT systemctl mask hibernation.target

echo "Installing Installation tools ..."
systemd-nspawn -D $TGT -- oma --no-check-dbus install \
	-y --no-refresh-topics \
	gparted select-language-gui xinit

echo "Enabling language selection UI ..."
mkdir -pv $TGT/usr/lib/systemd/system/sddm.service.wants
ln -sfv ../select-language-gui.service $TGT/usr/lib/systemd/system/sddm.service.wants/select-language-gui.service

echo "Cleaning up ..."
rm -r $TGT/var/cache/apt/archives
rm -r $TGT/var/lib/oma/*
rm -r $TGT/var/lib/apt/lists/*
if [ -e $TGT/etc/machine-id ] ; then
	rm $TGT/machine-id
fi
