DESCRIPTION = "ST Weston image + Ros base"
LICENSE = "MIT"
require recipes-st/images/st-image-weston.bb

# Allow up to ~1.3 GB
IMAGE_ROOTFS_MAXSIZE = "1300000"
# Optional: a little headroom to avoid near-limit churn
IMAGE_ROOTFS_EXTRA_SPACE = "32768"

IMAGE_INSTALL:append = " \
    ros-core \
    ros-base \
    rmw-cyclonedds-cpp \
    diagnostic-updater \
    diagnostic-aggregator \
"

# Keep ROS 2 user-space tracing only
IMAGE_INSTALL:append = " lttng-ust lttng-tools babeltrace2"


# Make sure kernel-side LTTng never lands in the image
# IMAGE_INSTALL:remove = " lttng-modules"

# Even if something *recommends* it, ignore
# BAD_RECOMMENDATIONS += " lttng-modules"
