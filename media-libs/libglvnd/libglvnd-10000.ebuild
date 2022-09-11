EAPI="8"

# This ebuild is a crutch for Gentoo packages which incorrectly depend
# on media-libs/libglvnd instead of virtual/opengl to indicate an OpenGL
# requirement.  It installs nothing and simply adds the virtual/opengl
# dependency.

DESCRIPTION="Dummy package to provide virtual/opengl dependency"
SLOT="0"
KEYWORDS="x86 amd64"
IUSE="+X abi_x86_32 abi_x86_64"

RDEPEND="virtual/opengl"
