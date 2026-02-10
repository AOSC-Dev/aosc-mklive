#!/bin/bash

# Utility routines used by aosc-mklive generators.
set -e

# Once sourced the environment will restore to sanity.
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8
export LC_ALL=C.UTF-8

# Force libmount to use mount(2) to mount overlayfs.
# The lowerdir option for the overlayfs will past the limit of fsconfig(2),
# which is 256 characters.
export LIBMOUNT_FORCE_MOUNT2=always

if [ "$LOCAL_TESTING" = "1" ] ; then
	SQUASHFS_COMP=none
	EROFS_COMP=none
fi

ARCHGROUPS=("mainline" "retro")
ARCHS_MAINLINE=("amd64" "arm64" "loongarch64" "loongson3" "ppc64el" "riscv64")
# Targets that are able to boot from CD are listed here.
ARCHS_RETRO=("i486" "alpha" "ia64" "mips64" "sparc64")

ab_match_archgroup() {
	for g in "${ARCHGROUPS[@]}" ; do
		var="ARCHS_${g^^}[@]"
		l1=("${!var}")
		l2=" ${l1[*]} "
		if [ "${l2// $ARCH /}" != "$l2" ] && \
			[ "$1" = "$g" ] ; then
			return 0
			break
		fi
	done
	return 1
}

ab_get_archgroup() {
	for g in "${ARCHGROUPS[@]}" ; do
		var="ARCHS_${g^^}[@]"
		l1=("${!var}")
		l2=" ${l1[*]} "
		if [ "${l2// $ARCH /}" != "$l2" ]; then
			echo -n "$g"
			break
		fi
	done
}

dbg() {
	echo -e "\033[0;37m[\033[34mDEBUG\033[37m]: $@\033[0m" >&2
}

info() {
	echo -e "\033[1;37m[\033[36mINFO\033[37m]: $@\033[0m" >&2
}

warn() {
	echo -e "\033[1;37m[\033[33mWARN\033[37m]: $@\033[0m" >&2
}

die() {
	echo -e "\033[1;37m[\033[31mERROR\033[37m]: $@\033[0m" >&2
	exit 1
}

bool() {
	local in="$1"
	local yes=" 1 y Y true yes YES ON "
	if [ "${yes/ $in /}" != "$yes" ] ; then
		return 0
	else
		return 1
	fi
}

fmt_bool() {
	if bool "$1" ; then
		echo -n "enabled"
	else
		echo -n "disabled"
	fi
}

gen_base() {
	local recipe="$1" config="$2"
	local topics="" t
	local scripts="" s
	for t in "${TOPICS[@]}" ; do
		topics="$topics --topics $t"
	done
	shift 2
	for s in "$@" ; do
		scripts="$scripts -s $s"
	done
	info "Bootstrapping base release ..."
	aoscbootstrap \
		--branch "stable" \
		--target "$WORKDIR"/base \
		--force -x \
		--mirror "$REPO" \
		--config "$config" \
		$topics \
		--arch "$ARCH" \
		-s "$AOSCBOOTSTRAP/scripts/reset-repo.sh" \
		-s "$AOSCBOOTSTRAP/scripts/enable-dkms.sh" \
		$scripts \
		--include-files "$recipe" || die "Failed to generate the base distribution!"
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
	touch "$STAMPDIR"/merged.lock
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
	info "Terminating container ..."
	if ! machinectl -q status isobuild &>/dev/null ; then
		die "The container is not running!"
	fi
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
	rm "$STAMPDIR"/merged.lock
	info "The container is terminated."
}

pack_squashfs() {
	local _comp outfile="$1" rootpath="$2"
	pushd "$WORKDIR/$tgt"
	case "${SQUASHFS_COMP:-xz}" in
		none)
			_comp="-no-compression"
			;;
		xz)
			_comp="-comp xz"
			;;
		zstd)
			# Default level is 15.
			_comp="-comp zstd"
			;;
		lz4hc)
			_comp="-comp lz4 -Xhc"
	;;
		*)
			die "Unsupported compression method '$SQUASHFS_COMP'."
			;;
	esac
	pushd "$rootpath"
	mksquashfs . ${outfile} \
		-noappend $_comp -processors $(nproc)
	popd
}

pack_erofs() {
	local _pagesize _comp outfile="$1" srcdir="$2"
	info "Creating an EROFS image \"$outfile\" from \"$srcdir\" ..."
	# Kernels with larger page size can mount images with smaller block
	# sizes. It does not work vice versa.
	case "$ARCH" in
		loongarch64|loongson3)
			# The installer uses 16K kernel
			_pagesize=16384
			;;
		ppc64el)
			_pagesize=65536
			;;
		*)
			# This is where the problem ocurrs:
			# We may use a machine running a 16K kernel to
			# generate EROFS images, which can not be mounted
			# using a 4KB kernel.
			_pagesize=4096
			;;
	esac
	case "${EROFS_COMP:-lzma}" in
		lzma)
			_comp="-zlzma,level=6"
			;;
		lz4hc)
			_comp="-zlz4hc,level=9"
			;;
		zstd)
			# zstd uses level 1 to 19.
			_comp="-zzstd,level=9"
			;;
		none)
			_comp=""
			;;
		*)
			die "Unsupported EROFS compression method."
			;;
	esac
	# Use a larger cluster size for better compression.
	# -E ztailpacking: Embed fragmented file contents into metadata
	#                  blocks.
	# # -E fragments: Pack small enough files into a special inode.
	# The two options above makes it behave like how NTFS stores smaller
	# files.
	mkfs.erofs "$outfile" "$srcdir" \
		-b "$_pagesize" \
		-C 524288 $_comp --worker $(nproc) -E fragments,ztailpacking
}

# $1: fstype
# $2: Output file
# $3: Path used as root (can not be a file)
packfs() {
	local fstype outfile rootpath parent
	fstype="$1"
	outfile="$2"
	rootpath="$3"
	parent="$(realpath -m $outfile)"
	parent="$(dirname $parent)"
	if [ ! -e "$rootpath" ] ; then
		die "Target path '$rootpath' does not exist."
	fi
	if [ ! -d "$rootpath" ] ; then
		die "Target path '$rootpath' is not a directory."
	fi
	if [ ! -e "$parent" ] ; then
		warn "Parent directory of '$outfile' does not exist, creating."
		mkdir -pv "$parent"
	fi
	case "$fstype" in
		squashfs)
			pack_squashfs "$outfile" "$rootpath"
			;;
		erofs)
			pack_erofs "$outfile" "$rootpath"
			;;
		*)
			die "Unknown filesystem type '$fstype'."
			;;
	esac
}

generate_overlay_opts() {
	local media="$1"
	local tgt="$2"
	local diff="$OVERLAYDIR"/"$tgt"
	local work="$WORKDIR"/"local"
	local _opts="lowerdir="
	local _lowerdirs=""
	IFS=$'\n'
	local deps=($(
		source "$TOP"/overlays/"$media"/"$tgt".conf
		echo "${OVERLAY_DEPS[*]}"
	))
	unset IFS
	for dep in "${deps[@]}" ; do
		_lowerdirs="$OVERLAYDIR"/"$dep:$_lowerdirs"
	done
	_lowerdirs="${_lowerdirs}${WORKDIR}/base"
	_opts="lowerdir=${_lowerdirs},upperdir=${diff},workdir=${work}"
	_opts="${_opts},redirect_dir=on"
	echo "$_opts"
}

generate_sysroot_opts() {
	local media="$1"
	local tgt="$2"
	local diff="$WORKDIR"/diff.tmp
	local work="$WORKDIR"/local.tmp
	local _opts="lowerdir="
	local _lowerdirs=""
	IFS=$'\n'
	local deps=($(
		source "$TOP"/sysroots/"$media"/"$tgt".conf
		for o in "${OVERLAY_DEP[@]}" ; do
			if [ "$o" = "base" ] ; then
				continue
			fi
			echo "$o"
		done
	))
	unset IFS
	for dep in "${deps[@]}" ; do
		if [ ! -d "$OVERLAYDIR"/"$dep" ] ; then
			die "$OVERLAYDIR/$dep does not exist ..."
		fi
		_lowerdirs="$OVERLAYDIR"/"$dep:$_lowerdirs"
	done
	_lowerdirs="${_lowerdirs}${WORKDIR}/base"
	_opts="lowerdir=${_lowerdirs},upperdir=${diff},workdir=${work}"
	_opts="${_opts},redirect_dir=on"
	echo "$_opts"
}

mount_overlay() {
	local _opts _dir tgt
	media="$1"
	tgt="$2"
	info "$tgt: Mounting container ..."
	mkdir -p ${OVERLAYDIR}/"$tgt"
	mkdir -p ${WORKDIR}/"merged"
	mkdir -p ${WORKDIR}/"local"
	_opts=$(generate_overlay_opts "$media" "$tgt")
	# mount -t overlay -o options source dest
	mount -t overlay \
		-o $_opts \
		overlay:$tgt \
		${WORKDIR}/merged
}

mount_sysroot() {
	local _opts _dir tgt
	media="$1"
	tgt="$2"
	info "$tgt: Mounting sysroot ..."
	mkdir -p ${WORKDIR}/"merged"
	mkdir -p ${WORKDIR}/"local.tmp"
	mkdir -p ${WORKDIR}/"diff.tmp"
	_opts=$(generate_sysroot_opts "$media" "$tgt")
	# mount -t overlay -o options source dest
	mount -t overlay \
		-o $_opts \
		overlay:$tgt \
		${WORKDIR}/merged
}

umount_container() {
	info "Umounting filesystem ..."
	umount -R "$WORKDIR"/merged
}

umount_sysroot() {
	info "Umounting sysroot ..."
	umount -R "$WORKDIR"/merged
	rm -r "${WORKDIR}"/"local.tmp"
	rm -r "${WORKDIR}"/"diff.tmp"
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

install_overlay() {
	local media tgt var pkgs
	if ! machinectl -q status isobuild &>/dev/null ; then
		die "Container is not started."
	fi
	media="$1"
	tgt="$2"
	info "Installing packages for $tgt ..."
	pkgs="$(
		source "$TOP"/overlays/"$media"/"$tgt".conf
		if [ -n "${RECIPE}" ] ; then
			pkgs="$(read_lst "${RECIPE}")"
		elif [ "${#PKGS[@]}" -gt 0 ] ; then
			pkgs="${PKGS[*]}"
		else
			pkgs="$(read_lst "$AOSCBOOTSTRAP"/recipes/"$tgt".lst)"
		fi
		echo "$pkgs"
	)"
	dbg "Packages to be installed: $pkgs"
	echo "deb ${REPO} stable main" > "$WORKDIR"/merged/etc/apt/sources.list
	systemd-run --wait -M isobuild -t -- \
		oma install --no-refresh-topics --yes $pkgs

	if [ "$tgt" = "desktop" ]; then
		echo "Removing plasma-workspace-wallpapers (installed as recommendation) ..."
		systemd-run --wait -M isobuild -t -- \
			dpkg --purge plasma-workspace-wallpapers
	fi

	info "Installation complete."
}

postinst_overlay() {
	local media scripts tgt var
	local SCRIPTS=(
		"$AOSCBOOTSTRAP/scripts/reset-repo.sh"
		"$TOP/scripts/cleanup.sh"
	)
	media="$1"
	tgt="$2"
	info "Running processing scripts for $tgt ..."
	if machinectl -q status isobuild &>/dev/null ; then
		die "Container is still running!"
	fi
	IFS=$'\n'
	SCRIPTS+=($(
		source "$TOP"/overlays/"$media"/"$tgt".conf
		echo "${ADDITIONAL_SCRIPTS[*]}"
	))

	dbg "Scripts to run: ${SCRIPTS[@]}"
	unset IFS
	for script in "${SCRIPTS[@]}" ; do
		_name=$(basename $script)
		dbg "Running script $_name ..."
		install -vm755 $script ${WORKDIR}/merged/
		systemd-nspawn -D ${WORKDIR}/merged --bind-ro $TOP:/run/mklive --bind "$ISODIR":/run/mklive-out -- \
			env ARCH="$ARCH" MKLIVE=1 bash /$_name
		info "Finished running $_name ."
		rm -v ${WORKDIR}/merged/$_name
		done
	info "Post processing complete."
}

pre_cleanup() {
	info "Cleaning up before generating ..."
	if [ -e "$STAMPDIR"/merged.lock ] ; then
		machinectl terminate isobuild &>/dev/null || true
		sleep 5
		rm "$STAMPDIR"/merged.lock
	fi
	umount -R ${WORKDIR}/merged &>/dev/null || true
	for layer in ${OVERLAYDIR}/* ; do
		umount -R $layer &>/dev/null || true
	done
	umount -R ${WORKDIR}/base &>/dev/null || true
	umount -R ${WORKDIR}/*-template-merged &>/dev/null || true
	rm -rf ${WORKDIR} &>/dev/null
	rm -rf ${ISODIR} &>/dev/null
	info "Finished cleaning up."
}

prepare() {
	info "Preparing to build ..."
	# aoscbootstrap won't run in existing directories.
	if [ ! -d "$PWD"/dracut/90aosc-livekit-loader ] ; then
		# We can not run this command as root.
		die "dracut module seems not cloned yet. Please run \`git submodule update --init --recursive\`."
	fi
	mkdir -pv ${WORKDIR}
	mkdir -pv ${STAMPDIR}
	mkdir -pv ${OVERLAYDIR}
	for layer in ${LAYERS[@]} ; do
		mkdir -pv ${OVERLAYDIR}/$layer
	done
	mkdir -pv ${WORKDIR}/merged
	mkdir -pv ${ISODIR}/boot
	mkdir -pv ${ISODIR}/manifest
	mkdir -pv ${OUT_PREFIX}/layers
	mkdir -pv ${OUT_PREFIX}/templates
	# File for gen-recipe.py to read. Contains recipe information.
	touch ${ISODIR}/sysroots.ini
	# File for the dracut loader to read. Contains layers and their dependencies.
	touch ${OUT_PREFIX}/livekit.conf
}

read_tgt_config() {
	local tgt="$1"
	if ! [ -e "$TOP"/targets/"$tgt"/"$ARCH".conf ] ; then
		die "Current architecture $ARCH does not support generating ISOs."
	fi
	source "$TOP"/targets/"$tgt"/"$ARCH".conf
	info "Target sysroot (s): ${SYSROOTS[@]}"
}

create_iso() {
	local volid="$1" testbed="$2" isodir="$3" output="$4"
	echo "Generating ISO with grub-mkrescue ..."
	# No need to restore the content - the contents has been archived.
	echo "deb ${REPO} stable main" > "$testbed"/etc/apt/sources.list
	systemd-nspawn -D $testbed \
		apt update
	systemd-nspawn -D $testbed \
		env DEBIAN_FRONTEND=noninteractive apt install --yes libisoburn grub
	systemd-nspawn -D $testbed --bind "$TOP":/mnt \
		grub-mkrescue \
			-o /mnt/"$output" \
			/mnt/"$isodir" -- -volid "$volid"
}

pack_templates() {
	local tgt outfile
	if machinectl -q status isobuild &>/dev/null ; then
		die "The container is still running."
	fi
	tgt="$1"
	if ! [ -d "${TOP}/templates/$tgt" ] && [ ! -e "$TOP/templates/$tgt.sh" ] ; then
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
	if [ -e "${TOP}"/templates/$tgt.sh ] ; then
		info "Running template script ..."
		# this script needs to be executed outside.
		env WORKDIR="$WORKDIR" OVERLAYDIR="$OVERLAYDIR" OUTDIR="$ISODIR" ARCH="$ARCH" TOP="$TOP" TGT=${WORKDIR}/$tgt-template-merged \
			bash "$TOP"/templates/$tgt.sh
	fi
	# If a template directory exists for overlay $tgt, pack them to
	# be overlayed.
	# If the script above creates files that should be overlayed,
	# they should create an directory with an empty file to indicate that.
	if [ -d "${TOP}/templates/$tgt" ] ; then
		info "Applying templates ..."
		chown -vR 0:0 $TOP/templates/$tgt
		cp -av $TOP/templates/$tgt/* ${WORKDIR}/$tgt-template-merged/
		chown -vR 1000:1001 ${WORKDIR}/$tgt-template-merged/home/live
		if [ "x$SUDO_UID" != "x" ] && [ "x$SUDO_GID" != "x" ] ; then
			chown -vR "$SUDO_UID:$SUDO_GID" $TOP/templates
		fi
		info "Umounting template layer ..."
		umount ${WORKDIR}/$tgt-template-merged
		info "Removing unused files and dpkg database ..."
		rm -rf "$WORKDIR"/"$tgt"-template/var/cache
		rm -rf "$WORKDIR"/"$tgt"-template/var/log
		# They are not needed anyway, since it is a template.
		# Otherwise they will interfere with other stacked overlays!
		rm -rf "$WORKDIR"/"$tgt"-template/var/lib/apt
		rm -rf "$WORKDIR"/"$tgt"-template/var/lib/dpkg
		info "Squashing template layer ..."
		outfile=${OUT_PREFIX}/templates/"$tgt"."$FSTYPE"
		packfs "$FSTYPE" "$outfile" "${WORKDIR}"/"$tgt"-template || \
			die "Failed to pack the template into a filesystem image."
	else
		info "Umounting template layer ..."
		umount ${WORKDIR}/$tgt-template-merged
	fi
}

get_info() {
	local inodes installedsize tgt dir
	tgt=$1
	info "$tgt: Getting information for recipe ..."
	if [ "x$tgt" = "xbase" ] ; then
		dir=${WORKDIR}/base
	elif [ "${tgt/livekit/}" != "$tgt" ] ; then
		info "Skipping for livekit sysroots ..."
		return
	else
		dir=${WORKDIR}/merged
	fi
	inodes=$(du -s --inodes $dir | awk '{ print $1 }')
	installedsize=$(du -sb $dir | awk '{ print $1 }')
	cat >> ${ISODIR}/sysroots.ini << EOF
[$tgt]
inodes=$inodes
installedsize=$installedsize

EOF
}

squash_overlay() {
	local tgt outfile
	if machinectl -q status isobuild &>/dev/null ; then
		die "The container living inside $_dir is still running."
	fi
	tgt=$1
	if [ ! -e "$OVERLAYDIR/$tgt" ] ; then
		die "$OVERLAYDIR/$tgt does not exist."
		return
	fi
	info "Squashing layer $tgt ..."
	if [ "x$1" = "xbase" ] ; then
		outfile="${OUT_PREFIX}/$tgt.$FSTYPE"
	else
		outfile="${OUT_PREFIX}/layers/$tgt.$FSTYPE"
	fi
	packfs "$FSTYPE" "$outfile" "$OVERLAYDIR"/"$tgt" || \
		die "Failed to pack layer into an filesystem image."
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
