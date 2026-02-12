# 在 STM32MP257F-DK 上启用 USART6 (A35/Linux)

## 概述

本文档记录了在 OpenSTLinux (Yocto) 工程中为 STM32MP257F-DK 开发板启用 USART6 的完整过程。
USART6 默认分配给 Cortex-M33 (CID2)，需要重新分配给 Cortex-A35 (CID1/Linux) 才能在 Linux 下使用。

- **硬件**: STM32MP257F-DK (MB1605 Var1.0 Rev.C-01)
- **BSP**: OpenSTLinux v6, stm32mp-r2
- **USART6 地址**: 0x40220000
- **USART6 引脚**: PF13 (TX), PF14 (RTS), PG0 (RX), PG1 (CTS)

## 背景知识

### STM32MP25 RIFSC 防火墙

STM32MP25 使用 RIFSC (Resource Isolation Firewall and Security Controller) 管理外设访问权限。
每个外设、GPIO 引脚、EXTI 中断都有独立的 RIF 配置，指定哪个 CID (Compartment ID) 可以访问：

| CID | 对应核心 |
|-----|---------|
| CID1 | Cortex-A35 (Linux) |
| CID2 | Cortex-M33 |
| CID3 | 其他 |

**关键点**: 启用一个外设不仅需要修改外设本身的 RIFSC，还需要同时修改其 GPIO 引脚和 EXTI 中断的 RIF 配置，否则 OP-TEE 的 IAC/SERC 防火墙会触发 panic。

### 涉及的 Device Tree 层次

STM32MP25 的 device tree 分为多个层次：

1. **external-dt** (OP-TEE RIF 配置 + Linux DTS overlay)
   - `stm32mp257f-dk-ca35tdcid-ostl-rif.dtsi` — RIFSC/GPIO/EXTI 防火墙配置
   - `stm32mp257f-dk-ca35tdcid-ostl.dts` — Linux 外设 overlay（status 控制）
2. **linux-stm32mp** (内核 DTS)
   - `stm32mp257f-dk.dts` — 内核主设备树

---

## 第一次修改：编译通过但运行时 OP-TEE panic

### 修改内容

仅修改了两处：
- RIFSC 中 USART6 从 CID2 改为 CID1
- Linux DTS overlay 和内核 DTS 中 USART6 status 从 "disabled" 改为 "okay"

### 运行时错误

烧录后板子启动时出现以下错误：

```
# 1. Linux 内核阶段 - GPIO 引脚权限被拒绝
stm32mp257-pinctrl: pin-93 (40220000.serial) status -13
stm32mp257-pinctrl: could not request pin 93 (PF13)
stm32-usart 40220000.serial: Error applying setting, reverse things back
stm32mp_exti: event 29 is reserved, secure
stm32-usart 40220000.serial: error -ENXIO: IRQ index 0 not found

# 2. OP-TEE 阶段 - 防火墙异常导致 panic
E/TC:0   stm32_iac_itr:192 IAC exceptions [159:128]: 0x10000000
E/TC:1   stm32_serc_handle_ilac:133 SERC exceptions [63:32]: 0x10
E/TC:0   stm32_iac_itr:197 IAC exception ID: 156
E/TC:1   stm32_serc_handle_ilac:139 SERC exception ID: 36
E/TC:0   Panic at core/drivers/firewall/stm32_iac.c:212 <stm32_iac_itr>
```

### 错误分析

| 错误 | 含义 |
|------|------|
| `SERC exception ID: 36` | RIFSC ID 36 = USART6，外设访问违规 |
| `IAC exception ID: 156` | GPIO/Pin 控制器访问违规 |
| `pin-93 status -13` | PF13 (USART6 TX) 被 RIFSC 拒绝 (-EACCES) |
| `event 29 is reserved` | EXTI1 event 29 (USART6 中断) 仍分配给 CID2 |

**根因**: 只改了 USART6 外设本身的 CID，没有改其 GPIO 引脚和 EXTI 中断的 CID 配置。

---

## 第二次修改：完整的 RIFSC 配置（最终成功版本）

### 需要修改的完整资源列表

| # | 资源 | 文件 | 修改 |
|---|------|------|------|
| 1 | RIFSC USART6 外设 | rif.dtsi `&rifsc` | `RIF_CID2` → `RIF_CID1`, `RIF_NPRIV` → `RIF_PRIV` |
| 2 | GPIOF pin 13 (TX) | rif.dtsi `&gpiof` | `RIF_CID2` → `RIF_CID1`, `RIF_NPRIV` → `RIF_PRIV` |
| 3 | GPIOF pin 14 (RTS) | rif.dtsi `&gpiof` | `RIF_CID2` → `RIF_CID1`, `RIF_NPRIV` → `RIF_PRIV` |
| 4 | GPIOG pin 1 (CTS) | rif.dtsi `&gpiog` | `RIF_CID2` → `RIF_CID1`, `RIF_NPRIV` → `RIF_PRIV` |
| 5 | EXTI1 event 29 (IRQ) | rif.dtsi `&exti1` | `RIF_CID2` → `RIF_CID1`, `RIF_NPRIV` → `RIF_PRIV` |
| 6 | Linux DTS overlay status | ostl.dts `&usart6` | `"disabled"` → `"okay"` |
| 7 | 内核 DTS status | stm32mp257f-dk.dts `&usart6` | `"disabled"` → `"okay"` |

> 注意: CID1 的外设统一使用 `RIF_PRIV`（特权模式），与 USART1/USART2 等已有 A35 外设保持一致。

### 新增/修改的文件

工程 `meta-myprod` layer 下共 4 个文件：

```
meta-myprod/
├── recipes-extended/external-dt/
│   ├── external-dt_%.bbappend                                    # bbappend
│   └── external-dt/
│       └── 0001-Enable-USART6-on-STM32MP257F-DK-for-A35.patch   # RIF + DTS overlay
└── recipes-kernel/linux/
    ├── linux-stm32mp_%.bbappend                                  # bbappend
    └── linux-stm32mp/
        └── 0001-Enable-USART6-on-stm32mp257f-dk.patch           # 内核 DTS
```

#### 1. external-dt bbappend

文件: `meta-myprod/recipes-extended/external-dt/external-dt_%.bbappend`

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://0001-Enable-USART6-on-STM32MP257F-DK-for-A35.patch"
```

#### 2. external-dt patch (RIFSC + DTS overlay)

文件: `meta-myprod/recipes-extended/external-dt/external-dt/0001-Enable-USART6-on-STM32MP257F-DK-for-A35.patch`

修改了 2 个文件，共 6 处改动：

**a) `stm32mp257f-dk-ca35tdcid-ostl.dts` (Linux DTS overlay)**
```diff
-	status = "disabled";
+	status = "okay";
```

**b) `stm32mp257f-dk-ca35tdcid-ostl-rif.dtsi` (RIFSC 防火墙配置)**

```diff
 # &rifsc — USART6 外设
-RIFPROT(STM32MP25_RIFSC_USART6_ID, RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_NPRIV, RIF_CID2, RIF_SEM_DIS, RIF_CFEN)
+RIFPROT(STM32MP25_RIFSC_USART6_ID, RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_PRIV, RIF_CID1, RIF_SEM_DIS, RIF_CFEN)

 # &exti1 — USART6 中断 (event 29)
-RIFPROT(RIF_EXTI1_RESOURCE(29), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_NPRIV, RIF_CID2, RIF_SEM_DIS, RIF_CFEN)
+RIFPROT(RIF_EXTI1_RESOURCE(29), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_PRIV, RIF_CID1, RIF_SEM_DIS, RIF_CFEN)

 # &gpiof — USART6 TX (pin 13) 和 RTS (pin 14)
-RIFPROT(RIF_IOPORT_PIN(13), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_NPRIV, RIF_CID2, RIF_SEM_DIS, RIF_CFEN)
-RIFPROT(RIF_IOPORT_PIN(14), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_NPRIV, RIF_CID2, RIF_SEM_DIS, RIF_CFEN)
+RIFPROT(RIF_IOPORT_PIN(13), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_PRIV, RIF_CID1, RIF_SEM_DIS, RIF_CFEN)
+RIFPROT(RIF_IOPORT_PIN(14), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_PRIV, RIF_CID1, RIF_SEM_DIS, RIF_CFEN)

 # &gpiog — USART6 CTS (pin 1)
-RIFPROT(RIF_IOPORT_PIN(1), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_NPRIV, RIF_CID2, RIF_SEM_DIS, RIF_CFEN)
+RIFPROT(RIF_IOPORT_PIN(1), RIF_UNUSED, RIF_UNLOCK, RIF_NSEC, RIF_PRIV, RIF_CID1, RIF_SEM_DIS, RIF_CFEN)
```

> 注意: GPIOG pin 0 (RX) 原本就是 `EMPTY_SEMWL` + `RIF_SEM_EN`（信号量共享模式），无需修改。

#### 3. linux-stm32mp bbappend

文件: `meta-myprod/recipes-kernel/linux/linux-stm32mp_%.bbappend`

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://0001-Enable-USART6-on-stm32mp257f-dk.patch"
```

#### 4. linux-stm32mp patch (内核 DTS)

文件: `meta-myprod/recipes-kernel/linux/linux-stm32mp/0001-Enable-USART6-on-stm32mp257f-dk.patch`

```diff
 # arch/arm64/boot/dts/st/stm32mp257f-dk.dts — &usart6 节点
-	status = "disabled";
+	status = "okay";
```

---

## 编译命令

### 环境初始化

```bash
cd /home/felux/Projects/st/openstlinux
DISTRO=openstlinux-weston MACHINE=stm32mp25-disco source layers/meta-st/scripts/envsetup.sh
```

### 清除受影响 recipe 的 stamps（强制重新编译）

修改 external-dt 的 RIFSC 配置后，需要强制重新编译 external-dt 及依赖它的 optee-os 和 tf-a：

```bash
# 删除 stamps 强制重新编译
find tmp-glibc/stamps -path '*external-dt*' -delete 2>/dev/null
find tmp-glibc/stamps -path '*optee-os-stm32mp*' -delete 2>/dev/null
find tmp-glibc/stamps -path '*tf-a-stm32mp*' -delete 2>/dev/null
```

> 如果权限允许，也可以使用 bitbake 命令清理:
> ```bash
> bitbake -c cleansstate external-dt optee-os-stm32mp tf-a-stm32mp
> ```

### 执行编译

```bash
BB_NUMBER_THREADS=8 PARALLEL_MAKE="-j8" bitbake mp257-st-ros-base
```

### 一键编译脚本

`run_build.sh`:

```bash
#!/bin/bash
cd /home/felux/Projects/st/openstlinux
DISTRO=openstlinux-weston MACHINE=stm32mp25-disco source layers/meta-st/scripts/envsetup.sh

# 强制重新编译 external-dt 及依赖的固件
find tmp-glibc/stamps -path '*external-dt*' -delete 2>/dev/null
find tmp-glibc/stamps -path '*optee-os-stm32mp*' -delete 2>/dev/null
find tmp-glibc/stamps -path '*tf-a-stm32mp*' -delete 2>/dev/null

BB_NUMBER_THREADS=8 PARALLEL_MAKE="-j8" bitbake mp257-st-ros-base
```

---

## 编译结果

```
NOTE: Tasks Summary: Attempted 17382 tasks of which 17013 didn't need to be rerun and all succeeded.
```

369 个任务重新编译（包括 external-dt、optee-os-stm32mp、tf-a-stm32mp 及其依赖），全部通过。

---

## 经验总结

1. **启用 STM32MP25 外设需要修改完整的 RIFSC 链路**：不仅是外设本身，还包括 GPIO 引脚、EXTI 中断。遗漏任何一个都会导致 OP-TEE IAC/SERC panic。

2. **不要直接 `rm -rf` Yocto 的 `tmp-glibc/` 子目录**。应该使用 `bitbake -c cleansstate <recipe>` 或删除对应的 stamps 文件，让 Bitbake 自己管理缓存一致性。

3. **不需要单独修改 OP-TEE 固件**。STM32MP25 的 RIFSC 配置完全由 external-dt 的 `rif.dtsi` 控制，OP-TEE 在启动时读取这个配置来编程 RIFSC 硬件。

4. **RIFPROT 参数参考已有的 CID1 外设**（如 USART1、USART2），使用 `RIF_PRIV` 而不是 `RIF_NPRIV`。

5. **如何查找外设的 RIFSC ID 和引脚**：
   - RIFSC ID: 在 `stm32mp257f-dk-ca35tdcid-ostl-rif.dtsi` 的 `&rifsc` 节点中查找
   - GPIO 引脚: 在内核 DTS 的 pinctrl 定义中查找（如 `usart6_pins_a`）
   - EXTI 事件号: 参考 STM32MP25 参考手册或运行时错误日志
