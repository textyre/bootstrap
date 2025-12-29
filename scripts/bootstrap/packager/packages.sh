#!/usr/bin/env bash
# Minimal host packages config — single bash array variable `packages`.
# Keep comments for grouping and per-package notes. The installer should
# `source` this file in bash and use "${packages[@]}".

packages=(
	# Xorg group: core X server and utilities
	xorg                        # Xorg core (xorg-server, etc.)
	xorg-apps                   # useful X utilities (xrandr, xrdb, xauth...)
	xorg-xinit                  # startx / xinit (moved into xorg group)
	xorg-drivers

	# i3 group: window manager and helpers
	i3                         # i3 window manager group (i3-wm, i3status)

	# Visuals and helpers
	picom                      # compositor (shadows, transparency)
	dmenu                      # minimal launcher menu

	# Graphics drivers
	mesa                        # OpenGL/GLX (Intel/AMD)

	# Session / greeter
	lightdm                    # display manager (optional)
	lightdm-gtk-greeter        # greeter for LightDM	

	# Terminal
	alacritty                  # modern GPU-accelerated terminal

	# Version control
	git                        # version control system

	# Dotfiles manager
	chezmoi                    # dotfiles manager (https://www.chezmoi.io/)

	# Runtime
	python                     # Python 3 interpreter

	# Fonts
	ttf-jetbrains-mono        # JetBrains Mono (only font requested)

	# IDE
	vim
)


aur_packages=(
	i3-rounded-border-patch-git 4.22.r31.gd06f97c4-1            # i3 rounded border patch
)
