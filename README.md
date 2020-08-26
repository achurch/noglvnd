noglvnd
=======

Gentoo overlay providing libglvnd-free OpenGL support.

This overlay is intended to replace existing packages in the Gentoo
Portage tree with versions that do not require the "libglvnd" library
(package `media-libs/libglvnd`), so that users who only use a single
OpenGL implementation do not need to install libglvnd.  All packages
which depend on libglvnd as a proxy for an OpenGL implementation have
been changed to instead depend on `virtual/opengl`.

This overlay force-disables the `libglvnd` USE flag in order to cancel
the effect of forced `USE=libglvnd` in the base Gentoo profile.
libglvnd support in packages is still available as an option, and the
USE mask will be removed if and when the Gentoo base profile removes
the forced flag.

For background, see: https://bugs.gentoo.org/show_bug.cgi?id=728286
