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

Because this overlay necessarily lags behind the Portage tree, updates to
overlaid packages which have not been synced into this overlay may cause
cause `emerge --update` to unintentionally switch to the libglvnd-enabled
version.  At present, `media-libs/mesa` will fail at the configuration
stage if libglvnd is not actually installed and `x11-base/xorg-server` will
raise a dependency error if `x11-drivers/nvidia-drivers[libglvnd]` is
installed, but `x11-drivers/nvidia-drivers` will build successfully and may
disrupt OpenGL use as a result.  Users may wish to explicitly mask the
upstream versions of these packages to avoid running into these problems,
by adding the following lines to `/etc/portage/package.mask` (or a file in
that directory, if it is a directory):
```
media-libs/mesa::gentoo
x11-base/xorg-server::gentoo
x11-base/nvidia-drivers::gentoo
```

libglvnd support is still available in packages as an option.  To use it
without removing this overlay, set `USE=libglvnd` in `make.conf` and add a
package mask for `media-libs/libglvnd::noglvnd`.

For background, see: https://bugs.gentoo.org/show_bug.cgi?id=728286
