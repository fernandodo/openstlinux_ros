# Debugging Yocto `devtool` and Environment Setup Issue

This document summarizes the challenges encountered while attempting to use `devtool` within the Gemini CLI environment for modifying Yocto recipes, and the steps taken to resolve them.

## Problem Description

The primary objective was to modify device tree source (DTS) files for OP-TEE and the Linux kernel within a Yocto project and apply these changes as patches via `devtool`. Initial attempts to use `devtool` commands (e.g., `devtool unpack`, `devtool modify`, `devtool finish`) consistently resulted in errors such as `devtool: command not found` or reports that the Yocto environment was not initialized, even after sourcing `layers/meta-st/scripts/envsetup.sh`.

## Root Cause Analysis

The root cause was a combination of factors related to how the Gemini CLI agent executes shell commands and how Yocto environment scripts (specifically `envsetup.sh` and `oe-init-build-env`) modify the shell's `PATH` and other environment variables.

1.  **Environment Isolation:** Each `run_shell_command` call by the Gemini CLI agent often operates in a new, isolated subshell environment. Environment changes (like `PATH` modifications) made by sourcing scripts in one `run_shell_command` might not persist or propagate correctly to subsequent, separate `run_shell_command` calls.
2.  **`PATH` Not Updated:** Initial `echo $PATH` commands confirmed that Yocto's `bin` directories (where `devtool` resides) were not consistently being added to the agent's `PATH`.
3.  **`devtool` Location:** `devtool` was not found in standard system `PATH` locations. A broad search located it at `/home/felux/Projects/st/openstlinux/layers/openembedded-core/scripts/devtool`.
4.  **Incomplete Environment for Direct Execution:** Even when `devtool` was executed using its absolute path, it reported `ERROR: This script can only be run after initialising the build environment`, indicating that other crucial environment variables (beyond just `PATH`) were not correctly set.

## Solution

The solution involved ensuring that the `source` command for the Yocto environment setup and the `devtool` command were executed within the *same shell context* to guarantee proper environment propagation.

**Key Discovery:** Executing the `source` command and the `devtool` command on a single line, separated by `&&`, resolved the environment issues. This forces the `devtool` command to run within the shell context where `source` has just modified the environment.

**Steps to resolve and generate patches:**

1.  **Locate `devtool` executable:** Identified `devtool`'s absolute path at `/home/felux/Projects/st/openstlinux/layers/openembedded-core/scripts/devtool`.
2.  **Modify Source Tree using `devtool modify`:**
    *   Command: `source layers/meta-st/scripts/envsetup.sh && devtool modify <recipe-name>`
    *   This successfully extracted the recipe's source into `build-openstlinuxweston-stm32mp25-disco/workspace/sources/<recipe-name>`.
3.  **Apply DTS Modifications:** Used `replace` to modify the target DTS file within the workspace.
4.  **Commit Changes in Workspace:** Navigated to the `devtool` workspace directory (`build-openstlinuxweston-stm32mp25-disco/workspace/sources/<recipe-name>`) and manually committed the changes using standard `git add` and `git commit` commands. This was crucial for `devtool finish` to detect the modifications.
5.  **Generate Patch using `devtool finish`:**
    *   Command: `source layers/meta-st/scripts/envsetup.sh && devtool finish -f <recipe-name> <layer-path>`
    *   The `-f` (force) flag was used to bypass "source tree not clean" warnings.
    *   `layer-path` was specified as `/home/felux/Projects/st/openstlinux/meta-myprod/`. This correctly generated the patch file and the corresponding `.bbappend` file within `meta-myprod`.

**Example Commands used:**

*   **For OP-TEE (`optee-os-stm32mp`):**
    ```bash
    source layers/meta-st/scripts/envsetup.sh && devtool modify optee-os-stm32mp
    # (after DTS modification and manual git commit in workspace)
    source layers/meta-st/scripts/envsetup.sh && devtool finish -f optee-os-stm32mp /home/felux/Projects/st/openstlinux/meta-myprod/
    ```

*   **For Linux Kernel (`linux-stm32mp`):**
    ```bash
    source layers/meta-st/scripts/envsetup.sh && devtool modify linux-stm32mp
    # (after DTS modification and manual git commit in workspace)
    source layers/meta-st/scripts/envsetup.sh && devtool finish -f linux-stm32mp /home/felux/Projects/st/openstlinux/meta-myprod/
    ```

## Post-Mortem and Cleanup

During the troubleshooting, due to confusion regarding `devtool finish`'s output, `bbappend` files were initially manually created in incorrect subdirectory locations, leading to duplicates. These duplicates were subsequently identified and removed to ensure the correct Yocto layer structure.

The correct structure for `bbappend` files created by `devtool finish` in a specified layer `meta-myprod` is:
*   `meta-myprod/recipes-security/optee/optee-os-stm32mp_%.bbappend`
*   `meta-myprod/recipes-kernel/linux/linux-stm32mp_%.bbappend`

Patches are placed in subdirectories like:
*   `meta-myprod/recipes-security/optee/optee-os-stm32mp/0001-OP-TEE-Enable-non-secure-access-for-USART6-RIF.patch`
*   `meta-myprod/recipes-kernel/linux/linux-stm32mp/0001-Linux-Enable-USART6-in-stm32mp257f-dk.dts.patch`