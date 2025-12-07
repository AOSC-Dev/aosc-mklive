#!/bin/bash -e

[ "$EUID" = "0" ] || { echo "Please run me as root." ; exit 1 ; }

set -e
source lib.bash

# aosc-mkinstaller: Generate an offline AOSC Installer image
# TODO usage

# Architecture of the target.
ARCH=${ARCH:-$(dpkg --print-architecture)}
# Topic parameter to pass to aoscbootstrap
TOPIC_OPT=
# Path to aoscbootstrap scripts and recipes
AOSCBOOTSTRAP=${AOSCBOOTSTRAP:-/usr/share/aoscbootstrap}
# Package repository to download packages from.
REPO=${REPO:-https://repo.aosc.io/debs}
# Where we put temorary files.
WORKDIR=${WORKDIR:-$PWD/work}
# Output directory.
OUTDIR=${OUTDIR:-$PWD/iso}
# Layers.
LAYERS=("desktop-common" "livekit" "desktop" "desktop-nvidia")
LAYERS_NONVIDIA=("desktop-common" "livekit" "desktop")
# Available layers for different archs.
LAYERS_amd64=("${LAYERS[@]}")
LAYERS_arm64=("${LAYERS[@]}")
LAYERS_loongarch64=("${LAYERS_NONVIDIA[@]}")
LAYERS_loongson3=("${LAYERS_NONVIDIA[@]}")
LAYERS_ppc64el=("${LAYERS_NONVIDIA[@]}")
LAYERS_riscv64=("${LAYERS_NONVIDIA[@]}")
# Layer dependencies.
# Layers that requires desktop.
LAYERS_desktop=("desktop-nvidia" "desktop-latx")
# Layers that requires desktop-common.
LAYERS_desktop_common=("desktop" "desktop-nvidia" "livekit" "livekit-nvidia" "desktop-latx")
# desktop-common packages.
PKGS_desktop_common=("adobe-source-code-pro" "firefox" "noto-fonts" "noto-cjk-fonts" "x11-base")
# desktop-latx packages, which is exclusive for loongarch64.
PKGS_desktop_latx=("latx" "wine")
# Sysroots that layers combined to.
# It does noting to the behaviour to this script.
# NOTE livekit must not present in this array. It will be added later.
# NOTE base must not present in this array, as base will get mounted automatically.
SYSROOTS=("desktop" "desktop-nvidia")
SYSROOTS_NONVIDIA=("desktop")
SYSROOTS_amd64=("${SYSROOTS[@]}")
SYSROOTS_arm64=("${SYSROOTS[@]}")
SYSROOTS_loongarch64=("${SYSROOTS_NONVIDIA[@]}")
SYSROOTS_loongson3=("${SYSROOTS_NONVIDIA[@]}")
SYSROOTS_ppc64el=("${SYSROOTS_NONVIDIA[@]}")
SYSROOTS_riscv64=("${SYSROOTS_NONVIDIA[@]}")

RECIPE_livekit="$PWD/recipes/livekit.lst"
RECIPE_desktop_nvidia="$AOSCBOOTSTRAP/recipes/desktop+nvidia.lst"

SCRIPTS=(
	"$AOSCBOOTSTRAP/scripts/reset-repo.sh"
	"$PWD/scripts/cleanup.sh"
)

SCRIPTS_base=(
	"$AOSCBOOTSTRAP/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_livekit=(
	"${PWD}/scripts/livekit.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_livekit_nvidia=(
	"$AOSCBOOTSTRAP/scripts/enable-nvidia-drivers.sh"
	"$AOSCBOOTSTRAP/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop_common=(
	"$AOSCBOOTSTRAP/scripts/enable-nvidia-drivers.sh"
	"$AOSCBOOTSTRAP/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop=(
	"$AOSCBOOTSTRAP/scripts/enable-nvidia-drivers.sh"
	"$AOSCBOOTSTRAP/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop_latx=(
	"${SCRIPTS[@]}"
)
SCRIPTS_desktop_nvidia=(
	"$AOSCBOOTSTRAP/scripts/enable-nvidia-drivers.sh"
	"$AOSCBOOTSTRAP/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)
SCRIPTS_server=(
	"$AOSCBOOTSTRAP/scripts/enable-dkms.sh"
	"${SCRIPTS[@]}"
)

sigint_hdl() {
	warn "Received Interrupt."
	info "Shutting down containers ..."
}

generate_overlay_opts() {
	local _opts _var _cmp tgt var arr
	# $1: layer name, e.g. livekit, desktop, desktop-nvidia.
	tgt=$1
	dir=${tgt}
	_cmp="\<${tgt}\>"
	var="LAYERS_$ARCH[@]"
	arr=("${!var}")
	if [ "${#arr[@]}" -lt 1 ] ; then
		die "Missing configuration for layer $tgt."
	fi
	if ! [[ "${arr[@]}" =~ $_cmp ]] ; then
		die "Layer $tgt is not found in \$$var."
	fi
	_opts="lowerdir="
	if [[ "${LAYERS_livekit[@]}" =~ $_cmp ]] && [ "$tgt" != "livekit" ] ; then
		_opts="${_opts}${WORKDIR}/livekit:"
	fi
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
	local _cnt _dir _timeout=30
	_dir="${WORKDIR}"/merged
	if ! machinectl -q status isobuild &>/dev/null ; then
		die "The container is not running!"
	fi
	info "Killing container ..."
	machinectl terminate isobuild
	_cnt=0
	if [ "$ARCH" != "$(dpkg --print-architecture)" ] ; then
		_timeout=300
	fi
	while machinectl -q status isobuild &>/dev/null ; do
		if [ $_cnt -ge $_timeout ] ; then
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
		--branch ${BRANCH:-stable} \
		--target $_dir \
		--force \
		--mirror ${REPO:-https://repo.aosc.io/debs} \
		--config "$AOSCBOOTSTRAP/config/aosc-mainline.toml" \
		-x \
		$TOPIC_OPT \
		--arch ${ARCH:-$(dpkg --print-architecture)} \
		-s \
			"$AOSCBOOTSTRAP/scripts/reset-repo.sh" \
		-s \
			"$AOSCBOOTSTRAP/scripts/enable-nvidia-drivers.sh" \
		-s \
			"$AOSCBOOTSTRAP/scripts/enable-dkms.sh" \
		--include-files "$AOSCBOOTSTRAP/recipes/base.lst"
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
		pkgs=$(read_lst $AOSCBOOTSTRAP/recipes/$tgt.lst)
	fi
	echo "deb ${REPO} stable main" > $WORKDIR/merged/etc/apt/sources.list
	systemd-run --wait -M isobuild -t -- \
		oma install --no-refresh-topics --yes $pkgs

	if [ "$tgt" = "desktop" ]; then
		echo "Removing plasma-workspace-wallpapers (installed as recommendation) ..."
		systemd-run --wait -M isobuild -t -- \
			dpkg --purge plasma-workspace-wallpapers
	fi

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
		systemd-nspawn -D ${WORKDIR}/merged --bind-ro $PWD:/run/mklive -- env INSTALLER=1 bash /$_name
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
	if ! [ -d "${PWD}/templates/$tgt" ] && [ ! -e "$PWD/templates/$tgt.sh" ] ; then
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
		env WORKDIR="$WORKDIR" OUTDIR="$OUTDIR" ARCH="$ARCH" TOP="$PWD" TGT=${WORKDIR}/$tgt-template-merged \
			bash "$PWD"/templates/$tgt.sh
	fi
	if [ -d "${PWD}/templates/$tgt" ] ; then
		info "Applying templates ..."
		chown -vR 0:0 $PWD/templates/$tgt
		cp -av $PWD/templates/$tgt/* ${WORKDIR}/$tgt-template-merged/
		chown -vR 1000:1001 ${WORKDIR}/$tgt-template-merged/home/live
		if [ "x$SUDO_UID" != "x" ] && [ "x$SUDO_GID" != "x" ] ; then
			chown -vR "$SUDO_UID:$SUDO_GID" $PWD/templates
		fi
	fi
	info "Umounting template layer ..."
	umount ${WORKDIR}/$tgt-template-merged
	info "Squashing template layer ..."
	outfile=${OUTDIR}/squashfs/templates/$tgt.squashfs
	pushd ${WORKDIR}/$tgt-template
	mksquashfs . ${outfile} \
		-noappend -comp xz -processors $(nproc)
	popd
}

get_info() {
	local inodes installedsize tgt dir
	tgt=$1
	info "$tgt: Getting information for recipe ..."
	if [ "x$tgt" = "xbase" ] ; then
		dir=${WORKDIR}/base
	else
		dir=${WORKDIR}/merged
	fi
	inodes=$(du -s --inodes $dir | awk '{ print $1 }')
	installedsize=$(du -sb $dir | awk '{ print $1 }')
	cat >> ${OUTDIR}/sysroots.ini << EOF
[$tgt]
inodes=$inodes
installedsize=$installedsize

EOF
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
	umount -R ${WORKDIR}/*-template-merged &>/dev/null || true
	rm -rf ${WORKDIR} &>/dev/null
	rm -rf ${OUTDIR} &>/dev/null
	info "Finished cleaning up."
}

prepare() {
	info "Preparing to build ..."
	# aoscbootstrap won't run in existing directories.
	if [ ! -d "$PWD"/dracut/90aosc-livekit-loader ] ; then
		# We can not run this command as root.
		die "dracut module seems not cloned yet. Please run \`git submodule update --init --recursive\`."
	fi
	mkdir -pv ${WORKDIR}/work
	for layer in ${LAYERS[@]} ; do
		mkdir -pv ${WORKDIR}/$layer
	done
	mkdir -pv ${WORKDIR}/merged
	mkdir -pv ${OUTDIR}/manifest
	mkdir -pv ${OUTDIR}/squashfs/layers
	mkdir -pv ${OUTDIR}/squashfs/templates
	# File for gen-recipe.py to read. Contains recipe information.
	touch ${OUTDIR}/sysroots.ini
	# File for the dracut loader to read. Contains layers and their dependencies.
	touch ${OUTDIR}/squashfs/layers.conf
	if [ "x$TOPICS" != "x" ] ; then
		for t in $TOPICS ; do
			info "Will opt in topic '$t'."
			TOPIC_OPT="$TOPIC_OPT --topics $t"
		done
	fi
}

dump_array() {
	# declare -p will print a command. We don't want that.
	local arrname arr str
	arrname=$1
	str="("
	if [ "x$arrname" = x ] ; then
		echo ""
	fi
	arrname="$arrname[@]"
	arr=(${!arrname})
	for e in "${arr[@]}" ; do
		str+="\"$e\" "
	done
	str="${str%% })"
	echo "$str"
}

_var="LAYERS_$ARCH[@]"
AVAIL_LAYERS=(${!_var})
_var="SYSROOTS_$ARCH[@]"
# livekit should not present in recipe.json.
AVAIL_SYSROOTS=(${!_var})
# Make a clone, to make base appear in the recipe.json.
AVAIL_SYSROOTS1=("${AVAIL_SYSROOTS[@]}" "base")
# Add livekit back.
AVAIL_SYSROOTS+=("livekit")
if [ "x$ARCH" = "xamd64" ] || [ "$xARCH" = "xarm64" ] ; then
	AVAIL_SYSROOTS+=("livekit-nvidia")
fi
if [ "${#AVAIL_LAYERS[@]}" -lt 1 ] || \
	[ "${#AVAIL_SYSROOTS[@]}" -lt 1 ] ; then
	die "There is no layers and sysroots defined for $ARCH. Check the script."
fi

info "Available layers for $ARCH: ${AVAIL_LAYERS[@]}"
info "Available sysroots for $ARCH: ${AVAIL_SYSROOTS[@]}"
pre_cleanup
prepare
cat > ${OUTDIR}/sysroots.ini << EOF
[installer]
sysroots=${AVAIL_SYSROOTS1[@]}

EOF
cat > ${OUTDIR}/squashfs/layers.conf << EOF
# All available layers.
LAYERS=$(dump_array AVAIL_LAYERS)
# All possible sysroots these layers combine to.
SYSROOT_LAYERS=$(dump_array AVAIL_SYSROOTS)
# What layers combine into a sysroot.
# Only dashes are allowed in the layer names - they are converted into
# underscores.
SYSROOT_DEP_desktop=("base" "desktop-common" "desktop")
SYSROOT_DEP_livekit=("base" "desktop-common" "livekit")
SYSROOT_DEP_server=("base" "server")
# it does nothing to the loader's behaviour, even if nvidia is not supported.
SYSROOT_DEP_desktop_nvidia=("base" "desktop-common" "desktop" "desktop-nvidia")
SYSROOT_DEP_desktop_latx=("base" "desktop-common" "desktop" "desktop-latx")
SYSROOT_DEP_livekit_nvidia=("base" "desktop-common" "desktop-nvidia" "livekit")

TEMPLATE_desktop_nvidia="desktop.squashfs"
TEMPLATE_desktop_latx="desktop.squashfs"
TEMPLATE_livekit_nvidia="livekit.squashfs"
EOF
bootstrap_base
get_info base
squash_layer base
for l in ${AVAIL_LAYERS[@]} ; do
	mount_layer $l
	start_container
	install_layer $l
	kill_container
	postinst_layer $l
	get_info $l
	pack_templates $l
	umount_layer $l
	squash_layer $l
done

info "Copying boot template ..."
make -C ${PWD}/boot/grub install

info "Generating recipe ..."
$PWD/gen-recipe.py ${OUTDIR}/sysroots.ini ${OUTDIR}/manifest/recipe.json

info "Downloading translated recipe ..."
curl -Lo "$OUTDIR"/manifest/recipe-i18n.json https://releases.aosc.io/manifest/recipe-i18n.json

info "Copying hooks ..."
cp -av ${PWD}/hooks ${OUTDIR}/squashfs/

info "Build successful!"
tree -h ${OUTDIR}
info "Total image size: $(du -sh ${OUTDIR}/squashfs | awk '{ print $1 }')"
