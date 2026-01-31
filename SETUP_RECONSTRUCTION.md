# OpenSTLinux + ROS 2 Setup Reconstruction

This document reconstructs the procedure used to set up the OpenSTLinux environment with ROS 2 (Jazzy) on the STM32MP257 platform (`stm32mp25-disco`).

## 1. Project Initialization (OpenSTLinux)

The project starts with the standard OpenSTLinux distribution from STMicroelectronics.

**Estimated Command:**
```bash
repo init -u https://github.com/STMicroelectronics/oe-manifest.git -b <branch_or_tag>
repo sync
```
*Note: The actual manifest in `.repo/manifests/default.xml` points to specific commits for `meta-st-openstlinux`, `meta-st-stm32mp`, etc., ensuring a reproducible build.*

## 2. ROS 2 Integration (meta-ros)

ROS 2 support is added via the `meta-ros` layer, specifically targeting the **Jazzy Jalisco** distribution.

### 2.1. Local Manifest
A local manifest was created at `.repo/local_manifests/meta-ros.xml` to fetch the `meta-ros` layer.

**Content of `.repo/local_manifests/meta-ros.xml`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="github-ros" fetch="https://github.com/" />
  <project path="layers/meta-ros"
           name="ros/meta-ros"
           remote="github"
           revision="e1380ca5b04ff6b1923e866ba2bb18fa613af8db" />
</manifest>
```

### 2.2. Sync
After creating the local manifest, the repository is synced again:
```bash
repo sync
```

## 3. Custom Layer Setup (`meta-myprod`)

A custom layer `meta-myprod` is used to host project-specific configurations and the main image recipe.

### 3.1. Layer Creation
The layer structure suggests it was created manually or via `bitbake-layers create-layer`.
*   **Path:** `meta-myprod/`
*   **Compatibility:** `scarthgap` (Yocto 5.0)

### 3.2. Workarounds (`make_wrappers.sh`)
A script `make_wrappers.sh` exists to generate wrapper recipes for `fuse`. This is likely required to resolve version conflicts or pathing issues between `meta-ros` generated recipes and the host system/other layers.

```bash
./make_wrappers.sh
```
*This script creates recipe wrappers in `meta-myprod/recipes-support/fuse/`.*

## 4. Build Configuration

### 4.1. `bblayers.conf`
The following layers were added to `conf/bblayers.conf` (absolute paths used in actual file):
*   `layers/meta-ros/meta-ros-common`
*   `layers/meta-ros/meta-ros2`
*   `layers/meta-ros/meta-ros2-jazzy`
*   `meta-myprod`
*   `layers/meta-openembedded/meta-oe`
*   `layers/meta-openembedded/meta-python`

### 4.2. `local.conf`
*   **Machine:** `stm32mp25-disco`
*   **Distro:** `openstlinux-weston`

## 5. Custom Image (`mp257-st-ros-base`)

The main build target is defined in `meta-myprod/recipes-st/images/mp257-st-ros-base.bb`.

**Features:**
*   **Base:** Inherits `st-image-weston` (Wayland/Weston graphics).
*   **ROS Packages:** Adds `ros-core`, `ros-base`, `rmw-cyclonedds-cpp`, `diagnostic-updater`, `diagnostic-aggregator`.
*   **Tracing:** Adds LTTng tools (`lttng-ust`, `lttng-tools`, `babeltrace2`).
*   **Size:** Configures rootfs max size to ~1.3GB.

## 6. Build Commands

To build the project:

1.  **Initialize Environment:**
    ```bash
    source layers/meta-st/scripts/envsetup.sh
    ```

2.  **Build Image:**
    ```bash
    BB_NUMBER_THREADS=8 PARALLEL_MAKE="-j8" bitbake mp257-st-ros-base
    ```

3.  **Build SDK (Optional):**
    ```bash
    bitbake mp257-st-ros-base -c populate_sdk
    ```
