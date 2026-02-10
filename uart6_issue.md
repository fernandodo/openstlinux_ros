
# USART6 Access Issue and Resolution for STM32MP257F-DK

## Problem

On the STM32MP257F-DK, attempting to enable `USART6` for the Cortex-A35 (Linux, `RIF_CID1`), which is by default assigned to the Cortex-M33 (`RIF_CID2`), resulted in a repeatable OP-TEE panic in `stm32_iac.c` (specifically `stm32_iac.c:212 <stm32_iac_itr>`). The Linux kernel would report a `-13 (EACCES)` error.

The root cause is the Resource Isolation Framework (RIF) configuration in OP-TEE, which restricts access to peripherals. A direct change in the TF-A device tree's `RIFPROT` was insufficient and caused secure world panics. The solution requires explicit permissioning in the OP-TEE device tree and enabling the peripheral in the Linux kernel device tree.

## Solution

The correct approach involves modifying both the OP-TEE device tree and the Linux kernel device tree, applying these changes via Yocto patches within a custom layer (`meta-myprod`).

### 1. OP-TEE Device Tree Modification

The OP-TEE device tree (`core/arch/arm/dts/stm32mp257f-dk.dts` within the OP-TEE source) needs to be modified to grant `RIF_CID1` (Cortex-A35) non-secure access to `USART6` and declare it.

**Specific Modifications to `stm32mp257f-dk.dts` (OP-TEE):**

*   **Add `&usart6` node:** This node needs to be added within the top-level `/` node, typically after the `shadow-prov` block.
    ```dts
            &usart6 {
                /* 授权配置：允许 CID1 (A35) 访问，非安全属性 */
                access-controllers = <&rifsc 42>; /* 42 是 USART6 在 RIF 中的 ID */
                status = "okay";
            };
    ```

*   **Add `s_usart6` sub-node to `&rifsc`:** This block needs to be appended to the file. It configures the RIFSC for `USART6` with the correct base address and non-secure access permissions for `RIF_CID1`.
    ```dts
    &rifsc {
        /* 确保 RIFSC 控制器中没有将 USART6 锁死在安全域 */
        s_usart6: usart6@40220000 {
            reg = <0x40220000 0x400>;
            /* 配置允许非安全访问 */
            st,prot = <RIF_ALLOW_NS_PRIV | RIF_ALLOW_NS_USER | RIF_ALLOW_S_PRIV | RIF_ALLOW_S_USER>;
            st,cid = <RIF_CID1_ALLOWED>; /* 允许 CID1 */
        };
    };
    ```
    **Note on `USART6` address:** The correct base address for `USART6` is `0x40220000`.

### 2. Linux Kernel Device Tree Modification

The Linux kernel device tree (`arch/arm64/boot/dts/st/stm32mp257f-dk.dts` within the Linux kernel source) needs to enable the `USART6` peripheral.

**Specific Modification to `stm32mp257f-dk.dts` (Linux Kernel):**

*   **Change `status` of `&usart6` node:** Modify the existing `&usart6` node to set its `status` property from `"disabled"` to `"okay"`.
    ```diff
    --- a/arch/arm64/boot/dts/st/stm32mp257f-dk.dts
    +++ b/arch/arm64/boot/dts/st/stm32mp257f-dk.dts
    @@ -x,y +x,y @@
     &usart6 {
             pinctrl-names = "default", "idle", "sleep";
             pinctrl-0 = <&usart6_pins_a>;
    -        status = "disabled";
    +        status = "okay";
     };
    ```

### 3. Yocto Integration

These modifications are applied via patches generated using `devtool` and integrated into the `meta-myprod` custom layer.

*   **OP-TEE Patch & bbappend:**
    *   Patch: `0001-OP-TEE-Implement-user-s-recommended-DTS-for-USART6-a.patch` (or similar name) containing the OP-TEE DTS changes.
    *   `optee-os-stm32mp_%.bbappend` in `meta-myprod/recipes-security/optee/` should reference this patch.
*   **Linux Kernel Patch & bbappend:**
    *   Patch: `0001-Linux-Enable-USART6-in-stm32mp257f-dk.dts.patch` (or similar name) containing the Linux DTS changes.
    *   `linux-stm32mp_%.bbappend` in `meta-myprod/recipes-kernel/linux/` should reference this patch.

---
