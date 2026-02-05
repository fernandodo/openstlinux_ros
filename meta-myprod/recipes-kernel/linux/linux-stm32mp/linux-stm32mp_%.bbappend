FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " 
    file://0001-tf-a-rifsc-enable-uart6-priv-cid1.patch;subdir=external-dt 
    file://0002-linux-dts-enable-uart6-status-okay.patch;subdir=external-dt 
"

# The patches must be applied to the source files *after* they are copied
# from the work-shared directory into the recipe's WORKDIR, but *before*
# the kernel build is configured. The do_configure:prepend hook is the
# ideal place for this. The 'subdir=external-dt' parameter in SRC_URI
# places the patches in the 'external-dt' directory, and the patch paths
# are relative to that.
do_configure:prepend() {
    cd ${WORKDIR}/external-dt
    oe_runmake_call patch -p1 < ${WORKDIR}/external-dt/0001-tf-a-rifsc-enable-uart6-priv-cid1.patch
    oe_runmake_call patch -p1 < ${WORKDIR}/external-dt/0002-linux-dts-enable-uart6-status-okay.patch
}

