DESCRIPTION = "ST Weston image + TurtleBot3 core"
LICENSE = "MIT"
require recipes-st/images/st-image-weston.bb

IMAGE_INSTALL:append = " \
    ros-core \
    ros-base \
    rmw-cyclonedds-cpp \
    diagnostic-updater \
    diagnostic-aggregator \
"
