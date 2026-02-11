#!/bin/bash
cd /home/felux/Projects/st/openstlinux
DISTRO=openstlinux-weston MACHINE=stm32mp25-disco source layers/meta-st/scripts/envsetup.sh

# Fix: sysroots-components was deleted, need to re-run both
# do_populate_sysroot (creates sysroots-components) and
# do_prepare_recipe_sysroot (links them into recipe workdirs)
echo "Removing sysroot-related stamps to force repopulation from sstate..."
find tmp-glibc/stamps -name '*do_populate_sysroot*' -delete 2>/dev/null
find tmp-glibc/stamps -name '*do_prepare_recipe_sysroot*' -delete 2>/dev/null

BB_NUMBER_THREADS=8 PARALLEL_MAKE="-j8" bitbake mp257-st-ros-base
