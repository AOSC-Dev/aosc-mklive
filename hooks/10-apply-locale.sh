#!/bin/bash
LANG=C.UTF-8

CMDLINEFILE=${CMDLINEFILE:-/proc/cmdline}

i "Trying to get kernel command line ..."
KERNEL_CMDLINE=($(cat $CMDLINEFILE))

for cmd in "${KERNEL_CMDLINE[@]}" ; do
	if [[ "$cmd" =~ LANG=* ]] ; then
		LANG=${cmd##LANG=}
		i "Caught LANG parameter, LANG=$LANG"
		break
	fi
done

if [ "$LANG" = "C.UTF-8" ] ; then
	i "LANG is set to C, assuming language was not chosen in the boot menu."
	return
fi
i "Applying language selection ..."
echo "LANG=$LANG" > /sysroot/etc/locale.conf
