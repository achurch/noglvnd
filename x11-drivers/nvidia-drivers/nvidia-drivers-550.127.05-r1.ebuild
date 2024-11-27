# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MODULES_OPTIONAL_IUSE=+modules
inherit desktop flag-o-matic linux-mod-r1 readme.gentoo-r1
inherit systemd toolchain-funcs unpacker user-info

MODULES_KERNEL_MAX=6.12
NV_URI="https://download.nvidia.com/XFree86/"

DESCRIPTION="NVIDIA Accelerated Graphics Driver"
HOMEPAGE="https://www.nvidia.com/"
SRC_URI="
	amd64? ( ${NV_URI}Linux-x86_64/${PV}/NVIDIA-Linux-x86_64-${PV}.run )
	arm64? ( ${NV_URI}Linux-aarch64/${PV}/NVIDIA-Linux-aarch64-${PV}.run )
	$(printf "${NV_URI}%s/%s-${PV}.tar.bz2 " \
		nvidia-{installer,modprobe,persistenced,settings,xconfig}{,})
	${NV_URI}NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-${PV}.tar.xz
"
# nvidia-installer is unused but here for GPL-2's "distribute sources"
S=${WORKDIR}

LICENSE="NVIDIA-r2 Apache-2.0 BSD BSD-2 GPL-2 MIT ZLIB curl openssl"
SLOT="0/${PV%%.*}"
KEYWORDS="-* amd64 ~arm64"
IUSE="+X abi_x86_32 abi_x86_64 kernel-open persistenced powerd +static-libs +tools wayland"
REQUIRED_USE="kernel-open? ( modules )"

IUSE+=" egl libglvnd"

COMMON_DEPEND="
	acct-group/video
	X? ( x11-libs/libpciaccess )
	persistenced? (
		acct-user/nvpd
		net-libs/libtirpc:=
	)
	tools? (
		>=app-accessibility/at-spi2-core-2.46:2
		dev-libs/glib:2
		dev-libs/jansson:=
		media-libs/harfbuzz:=
		x11-libs/cairo
		x11-libs/gdk-pixbuf:2
		x11-libs/gtk+:3[X]
		x11-libs/libX11
		x11-libs/libXext
		x11-libs/libXxf86vm
		x11-libs/pango
	)
"
RDEPEND="
	${COMMON_DEPEND}
	dev-libs/openssl:0/3
	sys-libs/glibc
	X? (
		x11-libs/libX11[abi_x86_32(-)?]
		x11-libs/libXext[abi_x86_32(-)?]
		!libglvnd? ( >=app-eselect/eselect-opengl-1.0.9 )
		libglvnd? (
			media-libs/libglvnd[X,abi_x86_32(-)?]
			!app-eselect/eselect-opengl
		)
	)
	powerd? ( sys-apps/dbus[abi_x86_32(-)?] )
	wayland? (
		gui-libs/egl-gbm
		>=gui-libs/egl-wayland-1.1.10
	)
"
DEPEND="
	${COMMON_DEPEND}
	static-libs? (
		x11-base/xorg-proto
		x11-libs/libX11
		x11-libs/libXext
	)
	tools? (
		sys-apps/dbus
		x11-base/xorg-proto
		x11-libs/libXrandr
		x11-libs/libXv
		x11-libs/libvdpau
		libglvnd? ( media-libs/libglvnd )
	)
"
BDEPEND="
	sys-devel/m4
	virtual/pkgconfig
"

QA_PREBUILT="lib/firmware/* opt/bin/* usr/lib*"

PATCHES=(
	"${FILESDIR}"/nvidia-modprobe-390.141-uvm-perms.patch
	"${FILESDIR}"/nvidia-settings-530.30.02-desktop.patch
	"${FILESDIR}"/nvidia-drivers-565.57.01-kernel-6.12.patch
)

pkg_setup() {
	use modules && [[ ${MERGE_TYPE} != binary ]] || return

	# do early before linux-mod-r1 so can use chkconfig to setup CONFIG_CHECK
	get_version
	require_configured_kernel

	local CONFIG_CHECK="
		PROC_FS
		~DRM_KMS_HELPER
		~SYSVIPC
		~!LOCKDEP
		~!PREEMPT_RT
		~!SLUB_DEBUG_ON
		!DEBUG_MUTEXES
		$(usev powerd '~CPU_FREQ')
	"

	kernel_is -ge 6 11 && linux_chkconfig_present DRM_FBDEV_EMULATION &&
		CONFIG_CHECK+=" DRM_TTM_HELPER"

	use amd64 && kernel_is -ge 5 8 && CONFIG_CHECK+=" X86_PAT" #817764

	use kernel-open && CONFIG_CHECK+=" MMU_NOTIFIER" #843827

	local drm_helper_msg="Cannot be directly selected in the kernel's config menus, and may need
	selection of a DRM device even if unused, e.g. CONFIG_DRM_AMDGPU=m or
	DRM_QXL=m, DRM_NOUVEAU=m also acceptable if a module and *not* built-in."
	local ERROR_DRM_KMS_HELPER="CONFIG_DRM_KMS_HELPER: is not set but needed for Xorg auto-detection
	of drivers (no custom config), and for wayland / nvidia-drm.modeset=1.
	${drm_helper_msg}"
	local ERROR_DRM_TTM_HELPER="CONFIG_DRM_TTM_HELPER: is not set but is needed to compile when using
	kernel version 6.11.x or newer while DRM_FBDEV_EMULATION is set.
	${drm_helper_msg}
	Many DRM devices like DRM_I915 cannot currently be used to enable this."
	local ERROR_MMU_NOTIFIER="CONFIG_MMU_NOTIFIER: is not set but needed to build with USE=kernel-open.
	Cannot be directly selected in the kernel's menuconfig, and may need
	selection of another option that requires it such as CONFIG_KVM."
	local ERROR_PREEMPT_RT="CONFIG_PREEMPT_RT: is set but is unsupported by NVIDIA upstream and
	will fail to build unless the env var IGNORE_PREEMPT_RT_PRESENCE=1 is
	set. Please do not report issues if run into e.g. kernel panics while
	ignoring this."

	linux-mod-r1_pkg_setup
}

src_prepare() {
	# make patches usable across versions
	rm nvidia-modprobe && mv nvidia-modprobe{-${PV},} || die
	rm nvidia-persistenced && mv nvidia-persistenced{-${PV},} || die
	rm nvidia-settings && mv nvidia-settings{-${PV},} || die
	rm nvidia-xconfig && mv nvidia-xconfig{-${PV},} || die
	mv NVIDIA-kernel-module-source-${PV} kernel-module-source || die

	default

	# prevent detection of incomplete kernel DRM support (bug #603818)
	sed 's/defined(CONFIG_DRM/defined(CONFIG_DRM_KMS_HELPER/g' \
		-i kernel{,-module-source/kernel-open}/conftest.sh || die

	# adjust service files
	sed 's/__USER__/nvpd/' \
		nvidia-persistenced/init/systemd/nvidia-persistenced.service.template \
		> "${T}"/nvidia-persistenced.service || die
	sed -i "s|/usr|${EPREFIX}/opt|" systemd/system/nvidia-powerd.service || die

	# use alternative vulkan icd option if USE=-X (bug #909181)
	use X || sed -i 's/"libGLX/"libEGL/' nvidia_{layers,icd}.json || die

	# enable nvidia-drm.modeset=1 by default with USE=wayland
	cp "${FILESDIR}"/nvidia-545.conf "${T}"/nvidia.conf || die
	use !wayland || sed -i '/^#.*modeset=1$/s/^#//' "${T}"/nvidia.conf || die

	# makefile attempts to install wayland library even if not built
	use wayland || sed -i 's/ WAYLAND_LIB_install$//' \
		nvidia-settings/src/Makefile || die
}

src_compile() {
	tc-export AR CC CXX LD OBJCOPY OBJDUMP PKG_CONFIG

	local xnvflags=-fPIC #840389
	# lto static libraries tend to cause problems without fat objects
	tc-is-lto && xnvflags+=" $(test-flags-CC -ffat-lto-objects)"

	NV_ARGS=(
		PREFIX="${EPREFIX}"/usr
		HOST_CC="$(tc-getBUILD_CC)"
		HOST_LD="$(tc-getBUILD_LD)"
		BUILD_GTK2LIB=
		NV_USE_BUNDLED_LIBJANSSON=0
		NV_VERBOSE=1 DO_STRIP= MANPAGE_GZIP= OUTPUTDIR=out
		WAYLAND_AVAILABLE=$(usex wayland 1 0)
		XNVCTRL_CFLAGS="${xnvflags}"
	)

	if use modules; then
		local o_cflags=${CFLAGS} o_cxxflags=${CXXFLAGS} o_ldflags=${LDFLAGS}

		# conftest.sh is broken with c23 due to func() changing meaning,
		# and then fails later due to ealier misdetections
		# TODO: try without now and then + drop modargs' CC= (bug #944092)
		KERNEL_CC+=" -std=gnu17"

		local modlistargs=video:kernel
		if use kernel-open; then
			modlistargs+=-module-source:kernel-module-source/kernel-open

			# environment flags are normally unused for modules, but nvidia
			# uses it for building the "blob" and it is a bit fragile
			filter-flags -fno-plt #912949
			filter-lto
			CC=${KERNEL_CC} CXX=${KERNEL_CXX} strip-unsupported-flags
		fi

		local modlist=( nvidia{,-drm,-modeset,-peermem,-uvm}=${modlistargs} )
		local modargs=(
			CC="${KERNEL_CC}" # needed for above gnu17 workaround
			IGNORE_CC_MISMATCH=yes NV_VERBOSE=1
			SYSOUT="${KV_OUT_DIR}" SYSSRC="${KV_DIR}"
		)

		# temporary workaround for bug #914468
		CPP="${KERNEL_CC} -E" tc-is-clang && addpredict "${KV_OUT_DIR}"

		linux-mod-r1_src_compile
		CFLAGS=${o_cflags} CXXFLAGS=${o_cxxflags} LDFLAGS=${o_ldflags}
	fi

	emake "${NV_ARGS[@]}" -C nvidia-modprobe
	use persistenced && emake "${NV_ARGS[@]}" -C nvidia-persistenced
	use X && emake "${NV_ARGS[@]}" -C nvidia-xconfig

	if use tools; then
		# avoid noisy *very* noisy logs with deprecation warnings
		CFLAGS="-Wno-deprecated-declarations ${CFLAGS}" \
			emake "${NV_ARGS[@]}" -C nvidia-settings
	elif use static-libs; then
		# pretend GTK+3 is available, not actually used (bug #880879)
		emake "${NV_ARGS[@]}" BUILD_GTK3LIB=1 \
			-C nvidia-settings/src out/libXNVCtrl.a
	fi
}

src_install() {
	local libdir=$(get_libdir) libdir32=$(ABI=x86 get_libdir)

	NV_ARGS+=( DESTDIR="${D}" LIBDIR="${ED}"/usr/${libdir} )

	local -A paths=(
		[APPLICATION_PROFILE]=/usr/share/nvidia
		[CUDA_ICD]=/etc/OpenCL/vendors
		[EGL_EXTERNAL_PLATFORM_JSON]=/usr/share/egl/egl_external_platform.d
		[FIRMWARE]=/lib/firmware/nvidia/${PV}
		[GBM_BACKEND_LIB_SYMLINK]=/usr/${libdir}/gbm
		[GLVND_EGL_ICD_JSON]=/usr/share/glvnd/egl_vendor.d
		[OPENGL_DATA]=/usr/share/nvidia
		[VULKAN_ICD_JSON]=/usr/share/vulkan
		[WINE_LIB]=/usr/${libdir}/nvidia/wine
		[XORG_OUTPUTCLASS_CONFIG]=/usr/share/X11/xorg.conf.d

		[GLX_MODULE_SHARED_LIB]=/usr/${libdir}/xorg/modules/extensions
		[GLX_MODULE_SYMLINK]=/usr/${libdir}/xorg/modules
		[XMODULE_SHARED_LIB]=/usr/${libdir}/xorg/modules
	)

	local skip_files=(
		$(usev !X "libGLX_nvidia libglxserver_nvidia")
		libGLX_indirect # non-glvnd unused fallback
		libnvidia-{gtk,wayland-client} nvidia-{settings,xconfig} # from source
		libnvidia-egl-gbm 15_nvidia_gbm # gui-libs/egl-gbm
		libnvidia-egl-wayland 10_nvidia_wayland # gui-libs/egl-wayland
		libnvidia-pkcs11.so # using the openssl3 version instead
	)
	local skip_modules=(
		$(usev !X "nvfbc vdpau xdriver")
		$(usev !modules gsp)
		$(usev !powerd powerd)
		installer nvpd # handled separately / built from source
	)
	local skip_types=(
		$(usex libglvnd 'GLVND_LIB GLVND_SYMLINK EGL_CLIENT.\* GLX_CLIENT.\*' 'GLVND_EGL_ICD_JSON')
		OPENCL_WRAPPER.\* # virtual/opencl
		DOCUMENTATION DOT_DESKTOP .\*_SRC DKMS_CONF SYSTEMD_UNIT # handled separately / unused
	)

	local DOCS=(
		README.txt NVIDIA_Changelog supported-gpus/supported-gpus.json
		nvidia-settings/doc/{FRAMELOCK,NV-CONTROL-API}.txt
	)
	local HTML_DOCS=( html/. )
	einstalldocs

	local DISABLE_AUTOFORMATTING=yes
	local DOC_CONTENTS="\
Trusted users should be in the 'video' group to use NVIDIA devices.
You can add yourself by using: gpasswd -a my-user video\
$(usev modules "

Like all out-of-tree kernel modules, it is necessary to rebuild
${PN} after upgrading or rebuilding the Linux kernel
by for example running \`emerge @module-rebuild\`. Alternatively,
if using a distribution kernel (sys-kernel/gentoo-kernel{,-bin}),
this can be automated by setting USE=dist-kernel globally.

Loaded kernel modules also must not mismatch with the installed
${PN} version (excluding -r revision), meaning should
ensure \`eselect kernel list\` points to the kernel that will be
booted before building and preferably reboot after upgrading
${PN} (the ebuild will emit a warning if mismatching).

See '${EPREFIX}/etc/modprobe.d/nvidia.conf' for modules options.")\
$(use amd64 && usev !abi_x86_32 "

Note that without USE=abi_x86_32 on ${PN}, 32bit applications
(typically using wine / steam) will not be able to use GPU acceleration.")

For additional information or for troubleshooting issues, please see
https://wiki.gentoo.org/wiki/NVIDIA/nvidia-drivers and NVIDIA's own
documentation that is installed alongside this README."
	readme.gentoo_create_doc

	if use modules; then
		linux-mod-r1_src_install

		insinto /etc/modprobe.d
		doins "${T}"/nvidia.conf

		# used for gpu verification with binpkgs (not kept, see pkg_preinst)
		insinto /usr/share/nvidia
		doins supported-gpus/supported-gpus.json
	fi

	emake "${NV_ARGS[@]}" -C nvidia-modprobe install
	fowners :video /usr/bin/nvidia-modprobe #505092
	fperms 4710 /usr/bin/nvidia-modprobe

	if use persistenced; then
		emake "${NV_ARGS[@]}" -C nvidia-persistenced install
		newconfd "${FILESDIR}"/nvidia-persistenced.confd nvidia-persistenced
		newinitd "${FILESDIR}"/nvidia-persistenced.initd nvidia-persistenced
		systemd_dounit "${T}"/nvidia-persistenced.service
	fi

	if use tools; then
		emake "${NV_ARGS[@]}" -C nvidia-settings install

		doicon nvidia-settings/doc/nvidia-settings.png
		domenu nvidia-settings/doc/nvidia-settings.desktop

		exeinto /etc/X11/xinit/xinitrc.d
		newexe "${FILESDIR}"/95-nvidia-settings-r1 95-nvidia-settings
	fi

	if use static-libs; then
		dolib.a nvidia-settings/src/out/libXNVCtrl.a

		insinto /usr/include/NVCtrl
		doins nvidia-settings/src/libXNVCtrl/NVCtrl{Lib,}.h
	fi

	use X && emake "${NV_ARGS[@]}" -C nvidia-xconfig install

	# mimic nvidia-installer by reading .manifest to install files
	# 0:file 1:perms 2:type 3+:subtype/arguments -:module
	local m into
	while IFS=' ' read -ra m; do
		! [[ ${#m[@]} -ge 2 && ${m[-1]} =~ MODULE: ]] ||
			[[ " ${m[0]##*/}" =~ ^(\ ${skip_files[*]/%/.*|\\} )$ ]] ||
			[[ " ${m[2]}" =~ ^(\ ${skip_types[*]/%/|\\} )$ ]] ||
			has ${m[-1]#MODULE:} "${skip_modules[@]}" && continue

		case ${m[2]} in
			MANPAGE)
				gzip -dc ${m[0]} | newman - ${m[0]%.gz}; assert
				continue
			;;
			GBM_BACKEND_LIB_SYMLINK) m[4]=../${m[4]};; # missing ../
			VDPAU_SYMLINK) m[4]=vdpau/; m[5]=${m[5]#vdpau/};; # .so to vdpau/
		esac

		if [[ -v 'paths[${m[2]}]' ]]; then
			into=${paths[${m[2]}]}
		elif [[ ${m[2]} == EXPLICIT_PATH ]]; then
			into=${m[3]}
		elif [[ ${m[2]} == *_BINARY ]]; then
			into=/opt/bin
		elif [[ ${m[3]} == COMPAT32 ]]; then
			use abi_x86_32 || continue
			into=/usr/${libdir32}
		elif [[ ${m[2]} == *_@(LIB|SYMLINK) ]]; then
			into=/usr/${libdir}
		else
			die "No known installation path for ${m[0]}"
		fi
		if ! use libglvnd && [[ ${m[2]} =~ GLVND_LIB|GLVND_SYMLINK|_CLIENT_ ]]; then
			into=${into}/opengl/nvidia/lib
		fi
		[[ ${m[3]: -2} == ?/ ]] && into+=/${m[3]%/}
		[[ ${m[4]: -2} == ?/ ]] && into+=/${m[4]%/}

		if [[ ${m[2]} =~ _SYMLINK$ ]]; then
			[[ ${m[4]: -1} == / ]] && m[4]=${m[5]}
			dosym ${m[4]} ${into}/${m[0]}
			continue
		fi
		[[ ${m[0]} =~ ^libnvidia-ngx.so|^libnvidia-egl-gbm.so ]] &&
			dosym ${m[0]} ${into}/${m[0]%.so*}.so.1 # soname not in .manifest

		printf -v m[1] %o $((m[1] | 0200)) # 444->644
		insopts -m${m[1]}
		insinto ${into}
		doins ${m[0]}
	done < .manifest || die
	insopts -m0644 # reset

	if ! use libglvnd && use egl; then
		insinto /usr/share/glvnd/egl_vendor.d
		doins 10_nvidia.json
	fi

	# MODULE:installer non-skipped extras
	: "$(systemd_get_sleepdir)"
	exeinto "${_#"${EPREFIX}"}"
	doexe systemd/system-sleep/nvidia
	dobin systemd/nvidia-sleep.sh
	systemd_dounit systemd/system/nvidia-{hibernate,resume,suspend}.service

	dobin nvidia-bug-report.sh

	# MODULE:powerd extras
	if use powerd; then
		newinitd "${FILESDIR}"/nvidia-powerd.initd nvidia-powerd #923117
		systemd_dounit systemd/system/nvidia-powerd.service

		insinto /usr/share/dbus-1/system.d
		doins nvidia-dbus.conf
	fi

	# enabling is needed for sleep to work properly and little reason not to do
	# it unconditionally for a better user experience
	: "$(systemd_get_systemunitdir)"
	local unitdir=${_#"${EPREFIX}"}
	# not using relative symlinks to match systemd's own links
	dosym {"${unitdir}",/etc/systemd/system/systemd-hibernate.service.wants}/nvidia-hibernate.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-hibernate.service.wants}/nvidia-resume.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-suspend.service.wants}/nvidia-suspend.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-suspend.service.wants}/nvidia-resume.service
	# also add a custom elogind hook to do the equivalent of the above
	exeinto /usr/lib/elogind/system-sleep
	newexe "${FILESDIR}"/system-sleep.elogind nvidia
	# <elogind-255.5 used a different path (bug #939216), keep a compat symlink
	# TODO: cleanup after 255.5 been stable for a few months
	dosym {/usr/lib,/"${libdir}"}/elogind/system-sleep/nvidia

	# needed with >=systemd-256 or may fail to resume with some setups
	# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1072722
	insinto "${unitdir}"/systemd-homed.service.d
	newins - 10-nvidia.conf <<-EOF
		[Service]
		Environment=SYSTEMD_HOME_LOCK_FREEZE_SESSION=false
	EOF
	insinto "${unitdir}"/systemd-suspend.service.d
	newins - 10-nvidia.conf <<-EOF
		[Service]
		Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
	EOF
	dosym -r "${unitdir}"/systemd-{suspend,hibernate}.service.d/10-nvidia.conf
	dosym -r "${unitdir}"/systemd-{suspend,hybrid-sleep}.service.d/10-nvidia.conf
	dosym -r "${unitdir}"/systemd-{suspend,suspend-then-hibernate}.service.d/10-nvidia.conf

	# symlink non-versioned so nvidia-settings can use it even if misdetected
	dosym nvidia-application-profiles-${PV}-key-documentation \
		${paths[APPLICATION_PROFILE]}/nvidia-application-profiles-key-documentation

	# don't attempt to strip firmware files (silences errors)
	dostrip -x ${paths[FIRMWARE]}

	# sandbox issues with /dev/nvidiactl others (bug #904292,#921578)
	# are widespread and sometime affect revdeps of packages built with
	# USE=opencl/cuda making it hard to manage in ebuilds (minimal set,
	# ebuilds should handle manually if need others or addwrite)
	insinto /etc/sandbox.d
	newins - 20nvidia <<<'SANDBOX_PREDICT="/dev/nvidiactl:/dev/nvidia-caps:/dev/char"'

	# dracut does not use /etc/modprobe.d if hostonly=no, but want to make sure
	# our settings are used for bug 932781#c8 and nouveau blacklist if either
	# modules are included (however, just best-effort without initramfs regen)
	if use modules; then
		echo "install_items+=\" ${EPREFIX}/etc/modprobe.d/nvidia.conf \"" >> \
			"${ED}"/usr/lib/dracut/dracut.conf.d/10-${PN}.conf || die
	fi
}

pkg_preinst() {
	has_version "${CATEGORY}/${PN}[kernel-open]" && NV_HAD_KERNEL_OPEN=
	has_version "${CATEGORY}/${PN}[wayland]" && NV_HAD_WAYLAND=

	use modules || return

	# set video group id based on live system (bug #491414)
	local g=$(egetent group video | cut -d: -f3)
	[[ ${g} =~ ^[0-9]+$ ]] || die "Failed to determine video group id (got '${g}')"
	sed -i "s/@VIDEOGID@/${g}/" "${ED}"/etc/modprobe.d/nvidia.conf || die

	# try to find driver mismatches using temporary supported-gpus.json
	for g in $(grep -l 0x10de /sys/bus/pci/devices/*/vendor 2>/dev/null); do
		g=$(grep -io "\"devid\":\"$(<${g%vendor}device)\"[^}]*branch\":\"[0-9]*" \
			"${ED}"/usr/share/nvidia/supported-gpus.json 2>/dev/null)
		if [[ ${g} ]]; then
			g=$((${g##*\"}+1))
			if ver_test -ge ${g}; then
				NV_LEGACY_MASK=">=${CATEGORY}/${PN}-${g}"
				break
			fi
		fi
	done
	rm "${ED}"/usr/share/nvidia/supported-gpus.json || die
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst

	if ! use libglvnd; then
		# Switch to the nvidia implementation
		use X && "${ROOT}"/usr/bin/eselect opengl set --use-old nvidia
	fi

	readme.gentoo_print_elog

	if [[ -r /proc/driver/nvidia/version &&
		$(</proc/driver/nvidia/version) != *"  ${PV}  "* ]]; then
		ewarn "Currently loaded NVIDIA modules do not match the newly installed"
		ewarn "libraries and may prevent launching GPU-accelerated applications."
		if use modules; then
			ewarn "Easiest way to fix this is normally to reboot. If still run into issues"
			ewarn "(e.g. API mismatch messages in the \`dmesg\` output), please verify"
			ewarn "that the running kernel is ${KV_FULL} and that (if used) the"
			ewarn "initramfs does not include NVIDIA modules (or at least, not old ones)."
		fi
	fi

	if [[ $(</proc/cmdline) == *slub_debug=[!-]* ]]; then
		ewarn "Detected that the current kernel command line is using 'slub_debug=',"
		ewarn "this may lead to system instability/freezes with this version of"
		ewarn "${PN}. Bug: https://bugs.gentoo.org/796329"
	fi

	if [[ -v NV_LEGACY_MASK ]]; then
		ewarn
		ewarn "***WARNING***"
		ewarn
		ewarn "You are installing a version of ${PN} known not to work"
		ewarn "with a GPU of the current system. If unwanted, add the mask:"
		if [[ -d ${EROOT}/etc/portage/package.mask ]]; then
			ewarn "  echo '${NV_LEGACY_MASK}' > ${EROOT}/etc/portage/package.mask/${PN}"
		else
			ewarn "  echo '${NV_LEGACY_MASK}' >> ${EROOT}/etc/portage/package.mask"
		fi
		ewarn "...then downgrade to a legacy[1] branch if possible (not all old versions"
		ewarn "are available or fully functional, may need to consider nouveau[2])."
		ewarn "[1] https://www.nvidia.com/object/IO_32667.html"
		ewarn "[2] https://wiki.gentoo.org/wiki/Nouveau"
	fi

	if use kernel-open && [[ ! -v NV_HAD_KERNEL_OPEN ]]; then
		ewarn
		ewarn "Open source variant of ${PN} was selected, be warned it is experimental"
		ewarn "and only for modern GPUs (e.g. GTX 1650+). Try to disable if run into issues."
		ewarn "Please also see: ${EROOT}/usr/share/doc/${PF}/html/kernel_open.html"
	fi

	if use wayland && use modules && [[ ! -v NV_HAD_WAYLAND ]]; then
		elog
		elog "With USE=wayland, this version of ${PN} sets nvidia-drm.modeset=1"
		elog "in '${EROOT}/etc/modprobe.d/nvidia.conf'. This feature is considered"
		elog "experimental but is required for wayland."
		elog
		elog "If you experience issues, either disable wayland or edit nvidia.conf."
		elog "Of note, may possibly cause issues with SLI and Reverse PRIME."
	fi

	# these can be removed after some time, only to help the transition
	# given users are unlikely to do further custom solutions if it works
	# (see also https://github.com/elogind/elogind/issues/272)
	if grep -riq "^[^#]*HandleNvidiaSleep=yes" "${EROOT}"/etc/elogind/sleep.conf.d/ 2>/dev/null
	then
		ewarn
		ewarn "!!! WARNING !!!"
		ewarn "Detected HandleNvidiaSleep=yes in ${EROOT}/etc/elogind/sleep.conf.d/."
		ewarn "This 'could' cause issues if used in combination with the new hook"
		ewarn "installed by the ebuild to handle sleep using the official upstream"
		ewarn "script. It is recommended to disable the option."
	fi
	if [[ $(realpath "${EROOT}"{/etc,{/usr,}/lib*}/elogind/system-sleep 2>/dev/null | \
		sort | uniq | xargs -d'\n' grep -Ril nvidia 2>/dev/null | wc -l) -gt 2 ]]
	then
		ewarn
		ewarn "!!! WARNING !!!"
		ewarn "Detected a custom script at ${EROOT}{/etc,{/usr,}/lib*}/elogind/system-sleep"
		ewarn "referencing NVIDIA. This version of ${PN} has installed its own"
		ewarn "hook at ${EROOT}/usr/lib/elogind/system-sleep/nvidia and it is recommended"
		ewarn "to remove the custom one to avoid potential issues."
		ewarn
		ewarn "Feel free to ignore this warning if you know the other NVIDIA-related"
		ewarn "scripts can be used together. The warning will be removed in the future."
	fi
	if [[ ${REPLACING_VERSIONS##* } ]] &&
		ver_test ${REPLACING_VERSIONS##* } -lt 550.107.02-r1 # may get repeated
	then
		elog
		elog "For suspend/sleep, 'NVreg_PreserveVideoMemoryAllocations=1' is now default"
		elog "with this version of ${PN}. This is recommended (or required) by"
		elog "major DEs especially with wayland but, *if* experience regressions with"
		elog "suspend, try reverting to =0 in '${EROOT}/etc/modprobe.d/nvidia.conf'."
		elog
		elog "May notably be an issue when using neither systemd nor elogind to suspend."
		elog
		elog "Also, the systemd suspend/hibernate/resume services are now enabled by"
		elog "default, and for openrc+elogind a similar hook has been installed."
	fi
}
