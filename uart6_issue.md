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

## 2. Failure Analysis

After rebooting the board, the UART6 device **did not appear**. The `/dev/ttySTM6` node was absent.

Analysis of the kernel log (`dmesg`) revealed the root cause:

**Key Kernel Log Message:**
```
[    1.328426] stm32-rifsc 42080000.bus: serial@40220000: Device driver will not be probed, error: -13
```

**Interpretation:**

-   **`stm32-rifsc`**: This is the **Resource Isolation Firewall** controller for the STM32MP processor. It's a security feature that controls which processing unit (e.g., Secure Cortex-M33, Non-secure Cortex-A35) can access which peripheral.
-   **`serial@40220000`**: This is the physical address of **`usart6`**.
-   **`error: -13`**: This corresponds to the Linux error code `EACCES`, which means **Permission Denied**.

**Conclusion:**
The Linux kernel, running in the non-secure world on the Cortex-A35 core, was explicitly **blocked by the RIFSC hardware firewall** from accessing the UART6 peripheral. This security configuration is established by the boot firmware (specifically, **Trusted Firmware-A / TF-A**) before the Linux kernel even starts. Modifying the Linux device tree alone is insufficient because the hardware access is denied at a lower level.

---

## 3. Next Action Plan: Modify TF-A Configuration

To fix this, we must modify the configuration of the boot firmware to grant Linux access to UART6.

**Objective:**
Modify the **Trusted Firmware-A (TF-A) device tree** to assign `usart6` to the non-secure world, making it accessible to the Linux kernel.

**High-Level Steps:**

1.  **Locate TF-A Device Tree Source:** We need to find the `.dts` or `.dtsi` files used by the `tf-a-stm32mp` Yocto recipe. This will involve inspecting the recipe's `SRC_URI` and source code.
2.  **Modify RIFSC Configuration:** Within the TF-A device tree, we must find the RIFSC node and change the peripheral allocation to move `usart6` (or its corresponding RIFSC ID) to the non-secure (NS) domain.
3.  **Create Patch and `bbappend`:** A patch file containing the device tree modification must be created. Then, a `tf-a-stm32mp_%.bbappend` file will be created in the `meta-myprod` layer to apply this patch during the build.
4.  **Full Rebuild and Deploy:** A full image rebuild (`bitbake mp257-st-ros-base`) will be necessary. This ensures that the bootloader firmware (e.g., `fip.bin`, containing the updated TF-A) is re-generated and included in the final image to be flashed to the board.

```