#!/bin/bash

# Utility routines used by aosc-mklive generators.
set -e

# Once sourced the environment will restore to sanity.
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8
export LC_ALL=C.UTF-8

if [ "$LOCAL_TESTING" = "1" ] ; then
	SQUASHFS_COMP=none
	EROFS_COMP=none
fi

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
		-C 1048576 $_comp --worker $(nproc) -E fragments,ztailpacking
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
