# keep build-time so CMake can find tracetools
DEPENDS:append = " tracetools"

# but do NOT drag it into the image at runtime
RDEPENDS:${PN}:remove = " tracetools "
RRECOMMENDS:${PN}:remove = " tracetools "

# (Optional belt & suspenders at image level)
# BAD_RECOMMENDATIONS avoids recommends pulling it back
# and keeps the LTTng stack out of the rootfs
# BAD_RECOMMENDATIONS += " tracetools lttng-ust lttng-tools lttng-modules babeltrace "