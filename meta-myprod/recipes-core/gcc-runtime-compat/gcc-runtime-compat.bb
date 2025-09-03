SUMMARY = "Compatibility package to satisfy RDEPENDS on gcc-runtime"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835af7b66f3d1c6f2b2b3d2c8f3b020"
inherit allarch

# Pretend to be gcc-runtime
RPROVIDES:${PN}  += "gcc-runtime"
RREPLACES:${PN}  += "gcc-runtime"
RCONFLICTS:${PN} += "gcc-runtime"

# Pull in the *real* runtime libs already provided by ST
RDEPENDS:${PN} = "libgcc libstdc++"

# No files — just dependency glue
ALLOW_EMPTY:${PN} = "1"
