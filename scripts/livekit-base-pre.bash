#!/bin/bash
# We have to pack up the dracut module and copy into the target sysroot
# where it will be untarred and installed into initrd.
mkdir -p "$WORKDIR"/base
tar cf $WORKDIR/base/dracut.tar dracut
