echo "Teaking xorg.conf to mark amdgpu as a discrete GPU ..."
cat >> /etc/X11/xorg.conf << EOF

Section "OutputClass"
    Identifier "Discrete GPU"
    MatchDriver "amdgpu"
    Option "PrimaryGPU" "yes"
EndSection
EOF
