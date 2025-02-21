# Begin ~/.bash_profile
# Written for Beyond Linux From Scratch
# by James Robertson <jameswrobertson@earthlink.net>
# updated by Bruce Dubbs <bdubbs@linuxfromscratch.org>

# Personal environment variables and startup programs.

# Personal aliases and functions should go in ~/.bashrc.  System wide
# environment variables and startup programs are in /etc/profile.
# System wide aliases and functions are in /etc/bashrc.

append () {
  # First remove the directory
  local IFS=':'
  local NEWPATH DIR
  for DIR in $PATH; do
     if [ "$DIR" != "$1" ]; then
       NEWPATH="${NEWPATH:+$NEWPATH:}$DIR"
     fi
  done
  # Then append the directory
  export PATH="$NEWPATH:$1"
}

# Set GCC_COLORS to something to trigger the tty-dependent auto coloring.
# Using a dummy value so we are not overriding the defaults.
export GCC_COLORS="${GCC_COLORS:-aosc-dummy=01}"

if [ -f "$HOME/.bashrc" ] ; then
  source $HOME/.bashrc
fi

# Start language selection menu only if we have not chosen one during GRUB.
# NOTE langselect returns 1 if it is already chosen
if /usr/bin/langdetect ; then
	if [ ! -n "$DISPLAY" ]; then
		select-language-tui
		source /etc/locale.conf
	fi
fi

# Display startup guide.
if [[ -e "$HOME"/.livekit_prompts/${LANG%%.*}.prompt ]]; then
    cat "$HOME"/.livekit_prompts/${LANG%%.*}.prompt
else
    cat "$HOME"/.livekit_prompts/en.prompt
fi

# Disable console powerdown.
setterm -powerdown

# End ~/.bash_profile
