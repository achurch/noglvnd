# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MODULES_OPTIONAL_IUSE=+modules
inherit desktop dot-a eapi9-pipestatus flag-o-matic linux-mod-r1 multilib
inherit readme.gentoo-r1 systemd toolchain-funcs unpacker user-info

MODULES_KERNEL_MAX=6.6
NV_URI="https://download.nvidia.com/XFree86/"

DESCRIPTION="NVIDIA Accelerated Graphics Driver"
HOMEPAGE="https://www.nvidia.com/"
SRC_URI="
	${NV_URI}Linux-x86_64/${PV}/NVIDIA-Linux-x86_64-${PV}.run
	$(printf "${NV_URI}%s/%s-${PV}.tar.bz2 " \
		nvidia-{installer,modprobe,persistenced,settings,xconfig}{,})
"
# nvidia-installer is unused but here for GPL-2's "distribute sources"
S=${WORKDIR}

LICENSE="NVIDIA-r2 BSD BSD-2 GPL-2 MIT ZLIB curl openssl"
SLOT="0/${PV%%.*}"
KEYWORDS="-* amd64"
IUSE="+X abi_x86_32 abi_x86_64 persistenced +static-libs +tools"

IUSE+=" egl libglvnd"

COMMON_DEPEND="
	acct-group/video
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
	sys-libs/glibc
	X? (
		x11-libs/libX11[abi_x86_32(-)?]
		x11-libs/libXext[abi_x86_32(-)?]
		!libglvnd? ( >=app-eselect/eselect-opengl-1.0.9 )
		libglvnd? (
			media-libs/libglvnd[X,abi_x86_32(-)]
			!app-eselect/eselect-opengl
		)
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
		libglvnd? (
			media-libs/libglvnd
		)
	)
"
BDEPEND="
	sys-devel/m4
	virtual/pkgconfig
"

# there is some non-prebuilt exceptions but rather not maintain a list
QA_PREBUILT="lib/firmware/* usr/bin/* usr/lib*"

PATCHES=(
	"${FILESDIR}"/nvidia-drivers-470.141.03-clang15.patch
	"${FILESDIR}"/nvidia-modprobe-390.141-uvm-perms.patch
	"${FILESDIR}"/nvidia-settings-390.144-desktop.patch
	"${FILESDIR}"/nvidia-settings-390.144-no-gtk2.patch
	"${FILESDIR}"/nvidia-settings-390.144-raw-ldflags.patch
)

pkg_setup() {
	use modules && [[ ${MERGE_TYPE} != binary ]] || return

	local CONFIG_CHECK="
		PROC_FS
		~DRM_KMS_HELPER
		~SYSVIPC
		~!AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT
		~!LOCKDEP
		~!SLUB_DEBUG_ON
		~!X86_KERNEL_IBT
		!DEBUG_MUTEXES
	"

	local ERROR_DRM_KMS_HELPER="CONFIG_DRM_KMS_HELPER: is not set but needed for Xorg auto-detection
	of drivers (no custom config), and for nvidia-drm.modeset=1 if used.
	Cannot be directly selected in the kernel's menuconfig, and may need
	selection of a DRM device even if unused, e.g. CONFIG_DRM_AMDGPU=m or
	DRM_I915=y, DRM_NOUVEAU=m also acceptable if a module and not built-in."

	local ERROR_X86_KERNEL_IBT="CONFIG_X86_KERNEL_IBT: is set and, if the CPU supports the feature,
	this *could* lead to modules load failure with ENDBR errors, or to
	broken CUDA/NVENC. Please ignore if not having issues, but otherwise
	try to unset or pass ibt=off to the kernel's command line." #911142

	use amd64 && kernel_is -ge 5 8 && CONFIG_CHECK+=" X86_PAT" #817764

	linux-mod-r1_pkg_setup
}

src_prepare() {
	# make patches usable across versions
	rm nvidia-modprobe && mv nvidia-modprobe{-${PV},} || die
	rm nvidia-persistenced && mv nvidia-persistenced{-${PV},} || die
	rm nvidia-settings && mv nvidia-settings{-${PV},} || die
	rm nvidia-xconfig && mv nvidia-xconfig{-${PV},} || die

	default

	# prevent detection of incomplete kernel DRM support (bug #603818)
	sed 's/defined(CONFIG_DRM/defined(CONFIG_DRM_KMS_HELPER/g' \
		-i kernel/conftest.sh || die

	sed 's/__USER__/nvpd/' \
		nvidia-persistenced/init/systemd/nvidia-persistenced.service.template \
		> "${T}"/nvidia-persistenced.service || die
}

src_compile() {
	tc-export AR CC CXX LD OBJCOPY OBJDUMP PKG_CONFIG
	local -x RAW_LDFLAGS="$(get_abi_LDFLAGS) $(raw-ldflags)" # raw-ldflags.patch

	# dead branch that will never be fixed and due for eventual removal,
	# so keeping lazy "fixes" (bug #921370)
	local kcflags=(
		-std=gnu17
		-Wno-error=implicit-function-declaration
		-Wno-error=incompatible-pointer-types
	)
	# not *FLAGS to ensure it's used everywhere including conftest.sh
	CC+=" $(test-flags-CC "${kcflags[@]}")"
	use modules && KERNEL_CC+=" $(CC=${KERNEL_CC} test-flags-CC "${kcflags[@]}")"

	# extra flags for the libXNVCtrl.a static library
	local xnvflags=-fPIC #840389
	tc-is-lto && xnvflags+=" $(test-flags-CC -ffat-lto-objects)"

	NV_ARGS=(
		PREFIX="${EPREFIX}"/usr
		HOST_CC="$(tc-getBUILD_CC)"
		HOST_LD="$(tc-getBUILD_LD)"
		NV_USE_BUNDLED_LIBJANSSON=0
		NV_VERBOSE=1 DO_STRIP= MANPAGE_GZIP= OUTPUTDIR=out
		XNVCTRL_CFLAGS="${xnvflags}"
	)

	local modlist=( nvidia{,-drm,-modeset,-peermem,-uvm}=video:kernel )
	local modargs=(
		CC="${KERNEL_CC}" # for the above kcflags workarounds
		IGNORE_CC_MISMATCH=yes NV_VERBOSE=1
		SYSOUT="${KV_OUT_DIR}" SYSSRC="${KV_DIR}"
	)

	# temporary workaround for bug #914468
	use modules && addpredict "${KV_OUT_DIR}"

	linux-mod-r1_src_compile
	emake "${NV_ARGS[@]}" -C nvidia-modprobe
	use persistenced && emake "${NV_ARGS[@]}" -C nvidia-persistenced
	use X && emake "${NV_ARGS[@]}" -C nvidia-xconfig

	if use tools; then
		# avoid noisy *very* noisy logs with deprecation warnings
		CFLAGS="-Wno-deprecated-declarations ${CFLAGS}" \
			emake "${NV_ARGS[@]}" -C nvidia-settings
	elif use static-libs; then
		emake "${NV_ARGS[@]}" -C nvidia-settings/src out/libXNVCtrl.a
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
		[GLVND_EGL_ICD_JSON]=/usr/share/glvnd/egl_vendor.d
		[VULKAN_ICD_JSON]=/usr/share/vulkan
		[WINE_LIB]=/usr/${libdir}/nvidia/wine
		[XORG_OUTPUTCLASS_CONFIG]=/usr/share/X11/xorg.conf.d

		[GLX_MODULE_SHARED_LIB]=/usr/${libdir}/xorg/modules/extensions
		[GLX_MODULE_SYMLINK]=/usr/${libdir}/xorg/modules
		[XMODULE_SHARED_LIB]=/usr/${libdir}/xorg/modules
	)

	local skip_files=(
		$(usev !X "libGLX_nvidia libglxserver_nvidia libnvidia-ifr")
		libGLX_indirect # non-glvnd unused fallback
		libnvidia-gtk nvidia-{settings,xconfig} # built from source
		# skip wayland-related files, largely broken with 470 at this point
		libnvidia-egl-wayland 10_nvidia_wayland libnvidia-vulkan-producer
	)
	local skip_modules=(
		$(usev !X "nvfbc vdpau xdriver")
		$(usev !modules gsp)
		installer nvpd # handled separately / built from source
	)
	local skip_types=(
		$(usex libglvnd 'GLVND_LIB GLVND_SYMLINK EGL_CLIENT.\* GLX_CLIENT.\*' 'GLVND_EGL_ICD_JSON')
		OPENCL_WRAPPER.\* # virtual/opencl
		DOCUMENTATION DOT_DESKTOP .\*_SRC DKMS_CONF # handled separately / unused
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
		newins "${FILESDIR}"/nvidia-470.conf nvidia.conf

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
		strip-lto-bytecode

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
				gzip -dc ${m[0]} | newman - ${m[0]%.gz}
				pipestatus || die
				continue
			;;
			VDPAU_SYMLINK) m[4]=vdpau/; m[5]=${m[5]#vdpau/};; # .so to vdpau/
		esac

		if [[ -v 'paths[${m[2]}]' ]]; then
			into=${paths[${m[2]}]}
		elif [[ ${m[2]} == *_BINARY ]]; then
			into=/usr/bin
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
		[[ ${m[0]} =~ ^libnvidia-ngx.so ]] &&
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

	# sandbox issues with /dev/nvidiactl (and /dev/char wrt bug #904292)
	# are widespread and sometime affect revdeps of packages built with
	# USE=opencl/cuda making it hard to manage in ebuilds (minimal set,
	# ebuilds should handle manually if need others or addwrite)
	insinto /etc/sandbox.d
	newins - 20nvidia <<<'SANDBOX_PREDICT="/dev/nvidiactl:/dev/char"'

	# dracut does not use /etc/modprobe.d if hostonly=no, but want to make sure
	# our settings are used for bug 932781#c8 and nouveau blacklist if either
	# modules are included (however, just best-effort without initramfs regen)
	if use modules; then
		echo "install_items+=\" ${EPREFIX}/etc/modprobe.d/nvidia.conf \"" >> \
			"${ED}"/usr/lib/dracut/dracut.conf.d/10-${PN}.conf || die
	fi
}

pkg_preinst() {
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

	ewarn
	ewarn "Be warned/reminded that the 470.xx branch reached end-of-life and"
	ewarn "NVIDIA is no longer fixing issues (including security). Free to keep"
	ewarn "using (for now) but it is recommended to either switch to nouveau or"
	ewarn "replace hardware. Will be kept in-tree while possible, but expect it"
	ewarn "to be removed likely in late 2027 or earlier if major issues arise."
	ewarn
	ewarn "Note that there is no plans to patch in support for kernels branches"
	ewarn "newer than 6.6.x which will be supported upstream until December 2026."
}
