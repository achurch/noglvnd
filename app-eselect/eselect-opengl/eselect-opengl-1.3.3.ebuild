# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Utility to switch between OpenGL implementations"
HOMEPAGE="https://wiki.gentoo.org/wiki/No_homepage"

# Source:
# http://www.opengl.org/registry/api/glext.h
# http://www.opengl.org/registry/api/glxext.h
GLEXT="85"
GLXEXT="34"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 hppa ~ia64 ~mips ppc ppc64 s390 sparc x86 ~amd64-linux ~x86-linux ~ppc-macos ~x64-macos ~x86-macos ~sparc-solaris ~x64-solaris ~x86-solaris"
IUSE=""

DEPEND="app-arch/xz-utils"
RDEPEND=">=app-admin/eselect-1.2.4"

S=${WORKDIR}

pkg_preinst() {
	# we may be moving the config file, so get it early
	OLD_IMPL=$(eselect opengl show)
}

pkg_postinst() {
	local shopt_save=$(shopt -p nullglob)
	shopt -s nullglob
	local opengl_dirs=( "${EROOT}"/usr/lib*/opengl )
	${shopt_save}
	if [[ -n ${opengl_dirs[@]} ]]; then
		# delete broken symlinks
		find "${opengl_dirs[@]}" -xtype l -delete
		# delete empty leftover directories (they confuse eselect)
		find "${opengl_dirs[@]}" -depth -type d -empty -exec rmdir -v {} +
	fi

	if [[ -n "${OLD_IMPL}" && "${OLD_IMPL}" != '(none)' ]] ; then
		eselect opengl set "${OLD_IMPL}"
	fi
	if [[ -f ${EROOT}/etc/env.d/03opengl ]]; then
		# remove the old file, moved now
		rm -vf "${EROOT}"/etc/env.d/03opengl
	fi
}

src_prepare() {
	cp -p "${FILESDIR}/opengl.eselect-${PV}" "${S}/"

	# don't die on Darwin users
	if [[ ${CHOST} == *-darwin* ]] ; then
		sed -i -e 's/libGL\.so/libGL.dylib/' opengl.eselect-${PV} || die
	fi
	eapply_user
}

src_install() {
	insinto "/usr/share/eselect/modules"
	newins opengl.eselect-${PV} opengl.eselect
}
