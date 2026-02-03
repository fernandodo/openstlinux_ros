# How to Enable UART6 on stm32mp25-disco with External Device Tree

This guide documents the procedure to enable `UART6` on the STMicroelectronics STM32MP25-Disco board when using an OpenSTLinux distribution that employs the **External Device Tree** mechanism.

## Background: The Problem

Standard device tree modification (e.g., via `devtool modify linux-stm32mp`) may not work as expected because the final Device Tree Blob (DTB) used by the board (`stm32mp257f-dk-ca35tdcid-ostl.dtb`) is generated from sources outside the main kernel source tree. These "external" sources override the settings in the base dts files.

The key is to modify the correct source file and ensure it gets compiled into the final `.dtb`.

---

## Part 1: Quick Verification (Manual Hack)

This method allows for rapid testing by directly modifying the generated intermediate DTS file and manually compiling it. This is ideal for quick verification before making the changes permanent.

### Step 1: Locate the Generated DTS Source

The source file for the board's specific DTB is generated during the build process. Find it here:

```bash
# Path to the generated Device Tree Source
GENERATED_DTS_PATH="build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux/stm32mp257f-dk-ca35tdcid-ostl.dts"
```

### Step 2: Modify the DTS File

Open the file from `GENERATED_DTS_PATH` in a text editor. Find the `&usart6` node and modify it.

**Change this:**
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

**To this:**
```dts
&usart6 {
        pinctrl-names = "default", "idle", "sleep";
        pinctrl-0 = <&usart6_pins_a>;
        pinctrl-1 = <&usart6_idle_pins_a>;
        pinctrl-2 = <&usart6_sleep_pins_a>;
        /*uart-has-rtscts; */ /* Comment out if not using hardware flow control */
        status = "okay";
};
```

### Step 3: Manually Compile the DTB

We will use the Device Tree Compiler (`dtc`) along with the C preprocessor (`cpp`) to compile our modified `.dts` into a `.dtb`. This bypasses the Yocto build system for speed.

First, ensure your environment is set up:
```bash
source layers/meta-st/scripts/envsetup.sh
```

Then, run the following commands from your project's root directory:
```bash
# Define path to kernel source for includes
KERNEL_SRC="build-openstlinuxweston-stm32mp25-disco/workspace/sources/linux-stm32mp"

# Define path to the DTS file we modified
DTS_FILE="build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux/stm32mp257f-dk-ca35tdcid-ostl.dts"

# Define the output DTB name
DTB_OUT="stm32mp257f-dk-ca35tdcid-ostl.dtb"

# 1. Pre-process the DTS to handle all #includes
cpp -nostdinc -I ${KERNEL_SRC}/include -I ${KERNEL_SRC}/arch/arm64/boot/dts/st \
    -undef -D__DTS__ -x assembler-with-cpp \
    ${DTS_FILE} > temp.dts.preprocessed

# 2. Compile the pre-processed file into a DTB
dtc -I dts -O dtb -o ${DTB_OUT} temp.dts.preprocessed

# 3. Clean up the temporary file
rm temp.dts.preprocessed

echo "Compilation complete. Output file is: ${DTB_OUT}"
```

### Step 4: Deploy and Test

The new `.dtb` file is now in your project root. Copy it to your board and reboot.

```bash
# 1. Backup the old DTB on the board (recommended)
ssh stm32ros2 "mv /boot/stm32mp257f-dk-ca35tdcid-ostl.dtb /boot/stm32mp257f-dk-ca35tdcid-ostl.dtb.bak_`date +%s`"

# 2. Copy the new DTB to the board
scp ./${DTB_OUT} stm32ros2:/boot/

# 3. Reboot the board
ssh stm32ros2 "reboot"
```

After rebooting, check for `/dev/ttySTM6` to confirm success.

---

## Part 2: Permanent Solution (The Yocto Way)

The manual hack is temporary and will be overwritten by a clean Yocto build. To make the change permanent, we need to create a patch and apply it using a `.bbappend` file in our `meta-myprod` layer.

### Step 1: Create a Patch File

First, copy the generated DTS file so we can create a `diff`.

```bash
# The source DTS file
DTS_FILE="build-openstlinuxweston-stm32mp25-disco/tmp-glibc/work-shared/stm32mp25-disco/external-dt/stm32mp2/a35-td/linux/stm32mp257f-dk-ca35tdcid-ostl.dts"

# Copy it to a .orig file
cp ${DTS_FILE} ${DTS_FILE}.orig

# Now, edit the original DTS_FILE and apply the UART6 changes (status="okay", etc.)

# After saving the changes, create the patch
diff -u ${DTS_FILE}.orig ${DTS_FILE} > 0001-enable-uart6-on-external-dt.patch

# Clean up
rm ${DTS_FILE}.orig
```
You now have a patch file named `0001-enable-uart6-on-external-dt.patch` in your project root.

### Step 2: Create the `bbappend` file

The External Device Tree is handled by the `linux-stm32mp` recipe. We will append to it.

1.  **Create the directory structure:**
    ```bash
    mkdir -p meta-myprod/recipes-kernel/linux/linux-stm32mp
    ```

2.  **Move the patch file:**
    ```bash
    mv 0001-enable-uart6-on-external-dt.patch meta-myprod/recipes-kernel/linux/linux-stm32mp/
    ```

3.  **Create the `bbappend` file:**
    Create a new file named `meta-myprod/recipes-kernel/linux/linux-stm32mp_%.bbappend` with the following content:

    ```bbappend
    # Apply our patch to the External Device Tree source
    SRC_URI:append = " file://0001-enable-uart6-on-external-dt.patch"

    # The patch targets a file that is not in the main kernel source tree (S),
    # so we need to tell bitbake where to apply it. The external DT sources
    # are copied to ${ST_EXTERNAL_DT_SRC}.
    ST_EXTERNAL_DT_PATH_pn-${PN} = "${ST_EXTERNAL_DT_SRC}/stm32mp2/a35-td/linux"
    PATCH_SEARCH_PATH:prepend = "${ST_EXTERNAL_DT_PATH_pn-${PN}}:"
    ```
    *Note: The `PATCH_SEARCH_PATH` trick tells bitbake to look for the file to patch in the external DT source directory as well.*

### Step 3: Rebuild the Image

With the `bbappend` and patch in place, you can now rebuild your image normally. The change will be automatically applied.

```bash
# Clean the linux-stm32mp recipe to ensure the patch is applied
bitbake linux-stm32mp -c cleanall

# Rebuild your main image
bitbake mp257-st-ros-base
```

The resulting `...ca35tdcid-ostl.dtb` in your `deploy` directory will now permanently have UART6 enabled.
