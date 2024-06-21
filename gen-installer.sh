#!/bin/bash -e

[ "$EUID" = "0" ] || { echo "Please run me as root." ; exit 1 ; }

# aosc-mkinstaller: Generate an offline AOSC Installer image
# TODO usage

# Reset to sanity
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Package repository to download packages from.
REPO=${REPO:-https://repo.aosc.io/debs}
# Where we put temorary files.
WORKDIR=${WORKDIR:-$PWD/work}
# Output directory.
OUTDIR=${OUTDIR:-$PWD/out}
# Layers.
LAYERS=("desktop-common" "desktop" "desktop-nvidia" "livekit" "server")
# Layers that requires desktop.
LAYERS_desktop=("desktop-nvidia")
# Layers that requires desktop-common.
LAYERS_desktop_common=("desktop" "desktop-nvidia" "livekit")
# desktop-common packages.
PKGS_desktop_common=("adobe-source-code-pro" "firefox" "noto-fonts" "noto-cjk-fonts" "x11-base")

RECIPE_livekit="$PWD/aosc-mklive/recipes/livekit.lst"
RECIPE_desktop_nvidia="$PWD/aoscbootstrap/recipes/desktop+nvidia.lst"

SCRIPTS=(
	"aoscbootstrap/scripts/reset-repo.sh"
	"aoscbootstrap/assets/cleanup.sh"
)

SCRIPTS_base=(
	"aoscbootstrap/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_livekit=(
	"aosc-mklive/scripts/livekit.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop_common=(
	"aoscbootstrap/scripts/enable-nvidia-drivers.sh"
	"aoscbootstrap/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop=(
	"aoscbootstrap/scripts/enable-nvidia-drivers.sh"
	"aoscbootstrap/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop_nvidia=(
	"aoscbootstrap/scripts/enable-nvidia-drivers.sh"
	"aoscbootstrap/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_server=(
	"aoscbootstrap/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)

info() {
	echo -e "\033[1;37m[\033[36mINFO\033[37m]: $@\033[0m" 
}

warn() {
	echo -e "\033[1;37m[\033[33mWARN\033[37m]: $@\033[0m" 
}

die() {
	echo -e "\033[1;37m[\033[31mERROR\033[37m]: $@\033[0m"
	exit 1
}

sigint_hdl() {
	warn "Received Interrupt."
	info "Shutting down containers ..."
}

generate_overlay_opts() {
	local _opts _var _cmp tgt
	# $1: layer name, e.g. livekit, desktop, desktop-nvidia.
	tgt=$1
	dir=${tgt}
	_cmp="\<${tgt}\>"
	if ! [[ "${LAYERS[@]}" =~ $_cmp ]] ; then
		die "Layer $tgt is not found in LAYERS."
	fi
	_opts="lowerdir="
	if [[ "${LAYERS_desktop[@]}" =~ $_cmp ]] && [ "$tgt" != "desktop" ] ; then
		_opts="${_opts}${WORKDIR}/desktop:"
	fi
	if [[ "${LAYERS_desktop_common[@]}" =~ $_cmp ]] && [ "$tgt" != "desktop-common" ]; then
		_opts="${_opts}${WORKDIR}/desktop-common:"
	fi
	_opts="${_opts}${WORKDIR}/base,"
	_opts="${_opts}upperdir=${WORKDIR}/$dir,"
	_opts="${_opts}workdir=${WORKDIR}/work,"
	_opts="${_opts}redirect_dir=on"
	echo "$_opts"
}

start_container() {
	local _cnt _dir
	_dir="${WORKDIR}"/merged
	if machinectl -q status isobuild &>/dev/null ; then
		die "The container living inside $_dir is still running."
	fi
	info "Booting up the container..."
	# No need to use different directories across each new containers, since we
	# power up one container at a time.
	systemd-nspawn -M isobuild -qbD $_dir > /dev/null &
	_cnt=0
	while ! systemd-run --wait -qM isobuild /usr/bin/true &>/dev/null ; do
		# We can not wait indefinitely.
		if [ "$_cnt" -ge "12" ] ; then
			die "Container is still starting after 1 minute!"
		fi
		sleep 5
		_cnt=$((_cnt+1))
	done
	info "Container is ready."
}

kill_container() {
	local _cnt _dir
	_dir="${WORKDIR}"/merged
	if ! machinectl -q status isobuild &>/dev/null ; then
		die "The container is not running!"
	fi
	info "Killing container ..."
	machinectl terminate isobuild
	_cnt=0
	while machinectl -q status isobuild &>/dev/null ; do
		if [ $_cnt -ge "30" ] ; then
			die "The container can not be terminated after 30 seconds."
		fi
		sleep 1
		_cnt=$((_cnt+1))
	done
	info "The container is terminated."
}

bootstrap_base() {
	local _dir
	_dir="${WORKDIR}"/base
	info "Bootstrapping base tarball ..."
	aoscbootstrap \
	${BRANCH:-stable} $_dir ${REPO} \
	--config "${PWD}/aoscbootstrap/config/aosc-mainline.toml" \
		-x \
		--arch ${ARCH:-$(dpkg --print-architecture)} \
		-s \
			"${PWD}/aoscbootstrap/scripts/reset-repo.sh" \
		-s \
			"${PWD}/aoscbootstrap/scripts/enable-nvidia-drivers.sh" \
		-s \
			"${PWD}/aoscbootstrap/scripts/enable-dkms.sh" \
		--include-files "${PWD}/aoscbootstrap/recipes/base.lst"
}

mount_layer() {
	local _opts _dir tgt
	tgt=$1
	info "$tgt: Mounting container ..."
	mkdir -p ${WORKDIR}/$tgt
	mkdir -p ${WORKDIR}/merged
	_opts=$(generate_overlay_opts $tgt)
	# mount -t overlay -o options source dest
	mount -t overlay \
		-o $_opts \
		overlay:$tgt \
		${WORKDIR}/merged
}

umount_layer() {
	info "Umounting filesystem ..."
	umount -R "$WORKDIR"/merged
}

read_lst() {
	local file line inc list
	file=$(realpath $1)
	if [ ! -e $file ] ; then
		die "List file $file is not found."
	fi
	list=""
	while read line ; do
		if [[ "$line" = %include* ]] ; then
			inc="${line##%include }"
			# Relative path
			if ! [[ "$inc" =~ ^/ ]] ; then
				p=$(dirname $file)
				inc="$p/$inc"
			fi
			list="${list[@]} $(read_lst $inc)"
		else
			list="$list $line"
		fi
	done < $file
	echo $list
}

install_layer() {
	local tgt var pkgs
	if ! machinectl -q status isobuild &>/dev/null ; then
		die "Container is not started."
	fi
	tgt=$1
	info "Installing packages for $tgt ..."
	var="RECIPE_${tgt//[-+]/_}"
	var1="PKGS_${tgt//[-+]/_}[*]"
	pkgs=""
	if [ "${!var}" ] ; then
		pkgs=$(read_lst ${!var})
	elif [ "${!var1}" ] ; then
		pkgs="${!var1}"
	else
		pkgs=$(read_lst $PWD/aoscbootstrap/recipes/$tgt.lst)
	fi
	echo "deb ${REPO} stable main" > $WORKDIR/merged/etc/apt/sources.list
	systemd-run --wait -M isobuild -t -- \
		oma install --yes $pkgs
	info "Installation complete."
}

postinst_layer() {
	local scripts tgt var
	if machinectl -q status isobuild &>/dev/null ; then
		die "Container is still running!"
	fi
	tgt=$1
	info "Running processing scripts for $tgt ..."
	var="SCRIPTS_${tgt//[-+]/_}[@]"
	scripts=("${!var}")
	for script in "${scripts[@]}" ; do
		_name=$(basename $script)
		info "Running script $_name ..."
		install -vm755 $script ${WORKDIR}/merged/
		systemd-nspawn -D ${WORKDIR}/merged -- bash /$_name
		info "Finished running $_name ."
		rm -v ${WORKDIR}/merged/$_name
		done
	info "Post processing complete."
}

squash_layer() {
	local tgt outfile
	if machinectl -q status isobuild &>/dev/null ; then
		die "The container living inside $_dir is still running."
	fi
	tgt=$1
	if [ ! -e "$WORKDIR/$tgt" ] ; then
		die "$WORKDIR/$tgt does not exist."
		return
	fi
	info "Squashing layer $tgt ..."
	pushd "$WORKDIR/$tgt"
	if [ "x$1" = "xbase" ] ; then
		outfile="${OUTDIR}/squashfs/$tgt.squashfs"
	else
		outfile="${OUTDIR}/squashfs/layers/$tgt.squashfs"
	fi
	mksquashfs . ${outfile} \
		-noappend -comp xz -processors $(nproc)
	popd
}

pack_templates() {
	local tgt outfile
	if machinectl -q status isobuild &>/dev/null ; then
		die "The container is still running."
	fi
	tgt=$1
	if ! [ -e "${PWD}/templates/$tgt" ] ; then
		info "No template detected for $tgt."
		return
	fi
	info "Preparing templates ..."
	mkdir -p ${WORKDIR}/$tgt-template
	mkdir -p ${WORKDIR}/$tgt-template-merged
	mkdir -p ${WORKDIR}/template-work
	mount -t overlay \
		-o "lowerdir=${WORKDIR}/merged,upperdir=${WORKDIR}/$tgt-template,workdir=${WORKDIR}/template-work,redirect_dir=on" \
		template:$tgt ${WORKDIR}/$tgt-template-merged
	if [ -e "${PWD}"/templates/$tgt.sh ] ; then
		info "Running template script ..."
		# this script needs to be executed outside.
		env WORKDIR="$WORKDIR" OUTDIR="$OUTDIR" TOP="$PWD" \
			bash "$PWD"/templates/$tgt.sh
	fi
	info "Applying templates ..."
	chown -vR 0:0 $PWD/templates/$tgt
	cp -av $PWD/templates/$tgt/* ${WORKDIR}/$tgt-template-merged/
	chown -vR 1000:1000 ${WORKDIR}/$tgt-template-merged/home/live
	info "Umounting template layer ..."
	umount ${WORKDIR}/$tgt-template-merged
	info "Squashing template layer ..."
	outfile=${OUTDIR}/squashfs/templates/$tgt.squashfs
	pushd ${WORKDIR}/$tgt-template
	mksquashfs . ${outfile} \
		-noappend -comp xz -processors $(nproc)
	popd
}

pre_cleanup() {
	info "Cleaning up before generating ..."
	machinectl terminate isobuild &>/dev/null || true
	sleep 5
	umount -R ${WORKDIR}/merged &>/dev/null || true
	for layer in ${LAYERS[@]} ; do
		umount -R ${WORKDIR}/$layer &>/dev/null || true
	done
	umount -R ${WORKDIR}/base &>/dev/null || true
	rm -rf ${WORKDIR} &>/dev/null
	info "Finished cleaning up."
}

prepare() {
	info "Preparing to build ..."
	# aoscbootstrap won't run in existing directories.
	mkdir -pv ${WORKDIR}/work
	for layer in ${LAYERS[@]} ; do
		mkdir -pv ${WORKDIR}/$layer
	done
	mkdir -pv ${WORKDIR}/merged
	mkdir -pv ${OUTDIR}/squashfs/layers
	mkdir -pv ${OUTDIR}/squashfs/templates
}

pre_cleanup
prepare
bootstrap_base
squash_layer base
for l in ${LAYERS[@]} ; do
	mount_layer $l
	start_container
	install_layer $l
	kill_container
	postinst_layer $l
	pack_templates $l
	umount_layer $l
	squash_layer $l
done
info "Build successful!"
tree -h ${OUTDIR}
info "Total image size: $(du -sh ${OUTDIR}/squashfs | awk '{ print $1 }')"
