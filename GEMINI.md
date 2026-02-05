# Gemini Context: OpenSTLinux with ROS 2

## Project Overview
This project is an **OpenSTLinux** (Yocto Project) distribution targeting the **STM32MP25** platform (`stm32mp25-disco`). It integrates **ROS 2 Jazzy** and uses a custom layer (`meta-myprod`) for project-specific configurations and recipe overrides.

## Remote Target & Build Environment

### Remote Target
- **SSH Alias:** `stm32ros2`
- **Usage:** Used for all `ssh` and `scp` commands to interact with the target board.

### Build Environment
1.  **Mandatory Setup:** Before running any `bitbake` command, the environment must be initialized:
    ```bash
    source layers/meta-st/scripts/envsetup.sh
    ```
2.  **Permission Fix (If Needed):** If `bitbake` commands fail with a `PermissionError` related to `uid_map`, it is likely due to AppArmor restrictions. This command resolves the issue:
    ```bash
    sudo apparmor_parser -R /etc/apparmor.d/unprivileged_userns
    ```

## Architecture

### Key Layers
*   **`layers/meta-st/`**: Official STMicroelectronics BSP and framework layers.
*   **`layers/meta-ros/`**: ROS 2 integration layers (specifically ROS 2 Jazzy).
*   **`meta-myprod/`**: Custom layer for this project.
    *   Used to override or wrap upstream recipes (e.g., `fuse`).
    *   Contains the build configuration overrides.
*   **`layers/meta-openembedded/`**: Standard OpenEmbedded dependencies.

### Configuration (`local.conf`)
*   **Machine**: `stm32mp25-disco`
*   **Distro**: `openstlinux-weston` (Wayland/Weston backend)

## Building and Running

### Common Commands
These commands are sourced from `commands.txt` and represent the standard workflow for this project.

**1. Build the Main Image (`mp257-st-ros-base`)**
Optimized for an 8-core machine:
```bash
BB_NUMBER_THREADS=8 PARALLEL_MAKE="-j8" bitbake mp257-st-ros-base
```

**2. Generate SDK**
```bash
bitbake mp257-st-ros-base -c populate_sdk
```

**3. Kernel Development**
Clean and configure the kernel:
```bash
bitbake -c clean virtual/kernel
bitbake virtual/kernel -c configure -f
bitbake virtual/kernel -c shared_workdir -f
```

**4. LTTng Modules**
Rebuild LTTng modules:
```bash
bitbake -c cleansstate lttng-modules
bitbake lttng-modules
```

## Helper Scripts

*   **`make_wrappers.sh`**: A script to automate the creation of recipe wrappers in `meta-myprod`.
    *   Currently configured to wrap `fuse` recipes from `meta-ros` into `meta-myprod` to handle versioning or path alignments.
*   **`keep-awake.sh`**: (Implied from `commands.txt`) A helper to prevent system sleep during long builds.

## Directory Structure
*   **`build-openstlinuxweston-stm32mp25-disco/`**: The active build directory.
*   **`.repo/`**: Repo tool directory, managing the git repositories for the layers.
*   **`commands.txt`**: A scratchpad file containing user-specific build commands and notes (in Chinese).
