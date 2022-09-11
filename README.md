noglvnd
=======

Gentoo overlay providing libglvnd-free OpenGL support.

This overlay is intended to replace existing packages in the Gentoo
Portage tree with versions that do not require the "libglvnd" library
(package `media-libs/libglvnd`), so that users who only use a single
OpenGL implementation do not need to install libglvnd.  This overlay
provides a dummy `libglvnd-10000` package which installs nothing and adds
a dependency on `virtual/opengl`, to satisfy packages which depend on
libglvnd as a proxy for an OpenGL implementation.

libglvnd support is still available in packages as an option.  To use it
without removing this overlay, set `USE=libglvnd` in `make.conf` and add a
package mask for `=media-libs/libglvnd-10000`.

This overlay force-disables the `libglvnd` USE flag in order to cancel
the effect of forced `USE=libglvnd` in the base Gentoo profile.  The
USE mask will be removed if and when the Gentoo base profile removes
the forced flag.

For background, see: https://bugs.gentoo.org/show_bug.cgi?id=728286
