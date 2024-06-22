[[ -d "$TGT" ]] || { echo "TGT is not set." ; exit 1 ; }

info "Creating a live user ... "
useradd -R $TGT -m -s /bin/bash live
usermod -R $TGT -aG audio,video,plugdev,tty live
chfn -R $TGT -f "Live session user"

info "Copying user skeletons ..."
for file in $(ls -A ${WORKDIR}/merged/etc/skel/) ; do
	cp -a $TGT/etc/skel/$file $TGT/home/live/
	chown -R 1000:1000 $TGT/home/live/$file
done

echo "live:live" | chpasswd -R $TGT

info "Enabling automatic login for SDDM ..."
sed -e 's/Relogin=false/Relogin=true/g' \
	-e 's/User=/User=live/g' \
	-e 's/Session=/Session=plasma/g' \
	-i ${WORKDIR}/merged/etc/sddm.conf
