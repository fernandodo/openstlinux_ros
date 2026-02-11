#!/bin/bash
cd /home/felux/Projects/st/openstlinux
DISTRO=openstlinux-weston MACHINE=stm32mp25-disco source layers/meta-st/scripts/envsetup.sh

# Force rebuild of external-dt and dependent firmware by removing stamps
echo "Removing stamps to force rebuild of external-dt, optee-os, tf-a..."
find tmp-glibc/stamps -path '*external-dt*' -delete 2>/dev/null
find tmp-glibc/stamps -path '*optee-os-stm32mp*' -delete 2>/dev/null
find tmp-glibc/stamps -path '*tf-a-stm32mp*' -delete 2>/dev/null

BB_NUMBER_THREADS=8 PARALLEL_MAKE="-j8" bitbake mp257-st-ros-base
