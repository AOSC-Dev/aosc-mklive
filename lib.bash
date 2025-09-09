#!/bin/bash

# Utility routines used by aosc-mklive generators.
set -e

# Once sourced the environment will restore to sanity.
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8
export LC_ALL=C.UTF-8

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
		*)
			die "Unknown filesystem type '$fstype'."
			;;
	esac
}

# $1: Output file
# $2: Path used as root (can not be a file)
pack_squashfs() {
	local rootpath outfile comp
	outfile="$1"
	rootpath="$2"
	if [ "$LOCAL_TESTING" = "1" ] ; then
		comp="-no-compression"
	else
		comp="-comp xz"
	fi
	info "Packing squashfs from '$rootpath' to '$outfile' ..."
	pushd "$rootpath"
	mksquashfs . ${outfile} \
		-noappend $comp -processors $(nproc)
	popd
}
