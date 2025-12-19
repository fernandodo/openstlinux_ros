# lttng-modules-dummy_1.0.bb
SUMMARY = "Dummy provider for lttng-modules"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

PROVIDES += "lttng-modules"
RPROVIDES:${PN} += "lttng-modules"
RCONFLICTS:${PN} += "lttng-modules"
RREPLACES:${PN} += "lttng-modules"
ALLOW_EMPTY:${PN} = "1"
