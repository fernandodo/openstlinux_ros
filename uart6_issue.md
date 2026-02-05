# Debugging UART6 Enablement on STM32MP257F-DK

This document records the steps taken to enable `UART6`, the analysis of its failure, and the future plan to resolve the issue.

## 1. Attempted Method: Manual Linux DTB Modification

The initial approach was to directly modify the Linux Device Tree to enable the `usart6` node, compile it, and deploy it to the board, bypassing a full Yocto build for quick verification.

### Step 1: Locate and Modify the Target DTS

The specific Device Tree Source (DTS) file being used by the board was identified in the build's temporary work directory:
- **File:** `build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux/stm32mp257f-dk-ca35tdcid-ostl.dts`

The `&usart6` node within this file was modified as follows:

**From:**
```dts
&usart6 {
        pinctrl-names = "default", "idle", "sleep";
        pinctrl-0 = <&usart6_pins_a>;
        pinctrl-1 = <&usart6_idle_pins_a>;
        pinctrl-2 = <&usart6_sleep_pins_a>;
        uart-has-rtscts;
        status = "disabled";
};
```

**To:**
```dts
&usart6 {
        pinctrl-names = "default", "idle", "sleep";
        pinctrl-0 = <&usart6_pins_a>;
        pinctrl-1 = <&usart6_idle_pins_a>;
        pinctrl-2 = <&usart6_sleep_pins_a>;
        /* uart-has-rtscts; */
        status = "okay";
};
```

### Step 2: Manually Compile the DTB

The modified DTS file was manually compiled into a Device Tree Blob (`.dtb`) using the `cpp` (pre-processor) and `dtc` (compiler) from the build environment.

```bash
# Define paths
KERNEL_SRC="build-openstlinuxweston-stm32mp25-disco/workspace/sources/linux-stm32mp"
DTS_FILE="build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux/stm32mp257f-dk-ca35tdcid-ostl.dts"
DTB_OUT="stm32mp257f-dk-ca35tdcid-ostl.dtb"

# Pre-process and Compile
cpp -nostdinc -I ${KERNEL_SRC}/include -I ${KERNEL_SRC}/arch/arm64/boot/dts/st \
    -undef -D__DTS__ -x assembler-with-cpp \
    ${DTS_FILE} > temp.dts.preprocessed

dtcs -I dts -O dtb -o ${DTB_OUT} temp.dts.preprocessed

rm temp.dts.preprocessed
```

### Step 3: Deploy to Target

The newly compiled `.dtb` was deployed to the target board (`stm32ros2`), and the board was rebooted.

---

## 2. Deeper Analysis: The Root Cause

### 2.1 Kernel Log Analysis

Analysis of the kernel log (`dmesg`) revealed the initial symptom:

**Key Kernel Log Message:**
```
[    1.328426] stm32-rifsc 42080000.bus: serial@40220000: Device driver will not be probed, error: -13
```
This `EACCES` (Permission Denied) error pointed towards a security firewall issue.

### 2.2 TF-A Device Tree Investigation

The root cause was found in the Trusted Firmware-A (TF-A) device tree, which configures the RIFSC (Resource Isolation Firewall).

- **File:** `build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/optee/stm32mp257f-dk-ca35tdcid-ostl-rif.dtsi`
- **Problematic Configuration:**
  ```dts
  &rifsc {
          st,protreg = <
                  ...
                  RIFPROT(STM32MP25_RIFSC_USART6_ID, RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_NPRIV, RIF_CID2, RIF_SEM_DIS, RIF_CFEN)
                  ...
          >;
  };
  ```

**Interpretation of `RIFPROT` for USART6:**

- `RIF_NSEC`: Correctly assigned to the Non-Secure world (where Linux runs).
- `RIF_NPRIV`: **Incorrect.** Assigned as Non-Privileged. The Linux kernel requires **Privileged (`RIF_PRIV`)** access to control peripherals.
- `RIF_CID2`: **Incorrect.** Assigned to Component ID 2 (typically the Cortex-M33 core). The Linux kernel runs on the Cortex-A35, which requires **CID 1 (`RIF_CID1`)**.

**Final Conclusion:**
The Linux kernel is blocked from accessing UART6 because the boot firmware (TF-A) configures the hardware firewall to deny it the necessary privilege level and component ID. Both the TF-A RIFSC configuration and the Linux device tree status must be corrected.

---

## 3. Deeper Investigation: The `external-dt` Mechanism

Further investigation into the Yocto build system revealed how these configurations are managed:

1.  **`external-dt.bbclass`**: The `linux-stm32mp` recipe inherits this class. This class is responsible for managing device tree files that are "external" to the main source code of a component.
2.  **`work-shared` as a Staging Area**: The directory `build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/${MACHINE}/external-dt/` is a **shared input tree (staging area)**. It contains the device tree sources (DTS/DTSI) that are ultimately consumed by both TF-A and the Linux kernel during their respective build processes. These files are typically generated or copied into this location by a specific recipe.
3.  **`bitbake -e` Analysis:**
    *   **`tf-a-stm32mp` recipe**:
        ```
        TF_A_CONFIG_OPTS_EXTDT=/home/felux/Projects/st/openstlinux/build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/tf-a
        ```
        This shows that `tf-a-stm32mp` consumes TF-A specific device tree files from the `external-dt` staging area via the `TFA_EXTERNAL_DT` makefile variable.
    *   **`linux-stm32mp` recipe**:
        ```
        KBUILD_EXTDTS=/home/felux/Projects/st/openstlinux/build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux
        ```
        This shows that `linux-stm32mp` consumes Linux specific device tree files from the `external-dt` staging area via the `KBUILD_EXTDTS` makefile variable.

**Conclusion from `bitbake -e`**: The `linux-stm32mp` recipe is the *provider* that populates the `work-shared/external-dt` directory with the device tree source files for both Linux and TF-A. The `tf-a-stm32mp` recipe then *consumes* the TF-A specific files from this shared location.

---

## 4. Next Action Plan: The Correct Permanent Solution (Yocto-friendly)

**Final Conclusion (Refined):**
The root cause is a misconfiguration in the TF-A's RIFSC (Resource Isolation Firewall) device tree, which assigns `USART6` to the wrong Component ID (CID2) and with insufficient privilege (`RIF_NPRIV`), thus blocking the Linux kernel (running on A35, CID1, requiring privileged access). This leads to the `EACCES` (`-13`) error. The solution requires a two-pronged approach: correcting the TF-A RIFSC configuration and explicitly enabling `usart6` in the Linux device tree. Both changes must be applied in a Yocto-compatible, maintainable way.

**The Fix:**

1.  **TF-A RIFSC Configuration Patch**: Modify the TF-A device tree source to allow the A35 core (CID1) privileged access to `USART6`.
    *   **Target File**: `build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/optee/stm32mp257f-dk-ca35tdcid-ostl-rif.dtsi`
    *   **Change**: Update the `RIFPROT` entry for `USART6` from `RIF_NPRIV, RIF_CID2` to `RIF_PRIV, RIF_CID1` (keeping `RIF_NSEC`).

2.  **Linux Device Tree Patch**: Enable `usart6` and ensure correct pin control.
    *   **Target File**: `build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux/stm32mp257f-dk-ca35tdcid-ostl.dts` (or an included `dtsi`).
    *   **Change**: Set `status = "okay"` and verify `pinctrl` points to the correct pins (e.g., connected to CN5 EXP_GPIO14/15).

**Yocto Implementation Strategy:**

The patches will be injected into the build process via a `bbappend` file in our custom layer (`meta-myprod`). Since the `linux-stm32mp` recipe is responsible for populating the `work-shared/external-dt` directory, its `bbappend` is the correct place to apply these modifications.

**High-Level Steps:**

1.  **Create Patch Files**:
    *   `0001-tf-a-rifsc-enable-uart6-priv-cid1.patch`: Modifies the TF-A RIFSC `dtsi` file.
    *   `0002-linux-dts-enable-uart6-status-okay.patch`: Modifies the Linux `dts` file.

2.  **Create `meta-myprod/recipes-kernel/linux/linux-stm32mp_%.bbappend`**:
    *   Add both patch files to the `SRC_URI`.
    *   Implement a `do_configure:prepend()` task hook. This hook will ensure that the patches are applied to the device tree files *after* they have been copied into the recipe's `WORKDIR` (which includes the `external-dt` files from `work-shared`), but *before* the main configuration and compilation steps for `linux-stm32mp`.

3.  **Rebuild and Deploy**:
    *   Clean the relevant `linux-stm32mp` recipe: `bitbake linux-stm32mp -c cleanall`.
    *   Rebuild the main image: `bitbake mp257-st-ros-base`. This will ensure both the Linux DTB and the TF-A firmware (`fip.bin`) are correctly regenerated with the new permissions.
    *   Flash the updated image or components to the board.

**Fastest Verification Path:**

To quickly ascertain if the RIFSC permission issue has been resolved:

1.  **Apply only the TF-A RIFSC configuration patch** (via `linux-stm32mp_%.bbappend`).
2.  **Rebuild and flash** the firmware (`fip.bin`).
3.  **Check `dmesg` on the target**: Look for the `driver will not be probed, error:-13` message for `serial@40220000`. If it's gone, the permission barrier is broken.
4.  **Then, apply the Linux DTS patch** to enable `usart6` and verify the appearance of `/dev/ttySTMx`.

