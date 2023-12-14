Create a minimal image for RPI zero 2w
======================================

## Toolchain
```bash
cd ~
git clone https://github.com/crosstool-ng/crosstool-ng.git  
cd crosstool-ng 
git checkout crosstool-ng-1.26.0        # currently latest stable version
./bootstrap
./configure --prefix=${PWD}
make
make install
cd ~/crosstool-ng
bin/ct-ng list-samples
bin/ct-ng show-aarch64-rpi3-linux-gnu
bin/ct-ng aarch64-rpi3-linux-gnu
bin/ct-ng menuconfig
```

### Modification
- Allow extending the toolchain after it is created (by default, it is created as read-only): 
    > Paths and misc options -> Render the toolchain read-only -> false

- Chane the tuple's vendor string:
    > Toolchain options -> Tuple's vendor string: Change rpi3 to rpizero2w

### Build
```bash
bin/ct-ng build
PATH=$PATH:~/x-tools/aarch64-rpizero2w-linux-gnu/bin
```

### Check
create file hello.c like this:
```c
#include <stdio.h>
#include <stdlib.h>
int main (int argc, char *argv[])
{
    printf ("Hello, world!\n");
    return 0;
}
```
```bash
aarch64-rpizero2w-linux-gnu-gcc hello.c -o hello
```

- add `-static` to link libraries staticaly
- move `hello` file to target and run it

## U-Boot
```bash
git clone git://git.denx.de/u-boot.git
cd u-boot
git checkout v2023.10           # currently latest stable version

PATH=$PATH:~/x-tools/aarch64-rpizero2w-linux-gnu/bin
export CROSS_COMPILE=aarch64-rpizero2w-linux-gnu-
export ARCH=arm64

make rpi_arm64_defconfig
make
```

### Prepare SD card
    scripts/format-sdcard.sh
```bash
cd ~
sudo apt install subversion
svn checkout https://github.com/raspberrypi/firmware/trunk/boot
cp boot/{bootcode.bin,start.elf,fixup.dat,bcm2710-rpi-zero-2-w.dtb} /media/${USER}/boot/
rm -rf boot
cp u-boot/u-boot.bin /media/${USER}/boot/

cat << EOF > config.txt
enable_uart=1
arm_64bit=1
kernel=u-boot.bin
EOF
mv config.txt /media/${USER}/boot/
```
- in this stage you can boot into U-Boot bootloader

## Linux Kernel
```bash
cd ~
git clone --depth=1 -b rpi-6.1.y https://github.com/raspberrypi/linux.git       # currently latest stable version
cd linux
make ARCH=arm64 CROSS_COMPILE=/home/cloner/x-tools/aarch64-rpizero2w-linux-gnu/bin/aarch64-rpizero2w-linux-gnu- bcm2711_defconfig
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=/home/cloner/x-tools/aarch64-rpizero2w-linux-gnu/bin/aarch64-rpizero2w-linux-gnu-
cp arch/arm64/boot/Image /media/${USER}/boot

cat << EOF > cmdline.txt
console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootwait
EOF
sudo cp cmdline.txt /media/${USER}/boot/

# clean up
rm cmdline.txt
```


## Configure U-Boot
```bash
cat << EOF > boot_cmd.txt
fatload mmc 0:1 \${kernel_addr_r} Image
fatload mmc 0:1 \${ramdisk_addr_r} uRamdisk
fatload mmc 0:1 \${fdt_addr} bcm2710-rpi-zero-2-w.dtb
booti \${kernel_addr_r} \${ramdisk_addr_r} \${fdt_addr}
EOF

~/u-boot/tools/mkimage -A arm64 -O linux -T script -C none -d boot_cmd.txt boot.scr
# Copy the compiled boot script to boot partition
sudo cp boot.scr /media/${USER}/boot/

# clean up
rm boot_cmd.txt boot.scr 
```
- up to here your board should boot up and kernel starts normally but as we do not add Root filesystem, it ends up with panic

# Root filesystem (Staging Area)
```bash
cd ~
mkdir rootfs
cd rootfs
mkdir {bin,dev,etc,home,lib64,proc,sbin,sys,tmp,usr,var}
mkdir usr/{bin,lib,sbin}
mkdir var/log

# Create a symbolink lib pointing to lib64
ln -s lib64 lib

# Change the owner of the directories to be root
# Because current user doesn't exist on target device
sudo chown -R root:root *
```

## Busybox
```bash
cd ~
git clone git://busybox.net/busybox.git
cd busybox
git checkout 1_36_1             # latest stable version

# Config
make distclean
CROSS_COMPILE=${HOME}/x-tools/aarch64-rpizero2w-linux-gnu/bin/aarch64-rpizero2w-linux-gnu-
make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" defconfig
# Change the install directory to be the one just created
# Note that you should change usename in this command
sed -i 's%^CONFIG_PREFIX=.*$%CONFIG_PREFIX="/home/cloner/rootfs"%' .config

# Build
make CROSS_COMPILE="$CROSS_COMPILE"

# Install
# Use sudo because the directory is now owned by root
sudo make CROSS_COMPILE="$CROSS_COMPILE" install

```
- Note that you can use ToyBox instead which is very often used in Android devices

## Required Libraries
You need to copy shared libraries from toolchain to the staging directory.
```bash
cd ~/rootfs
PATH=$PATH:~/x-tools/aarch64-rpizero2w-linux-gnu/bin
aarch64-rpizero2w-linux-gnu-readelf -a ~/rootfs/bin/busybox | grep -E "(program interpreter)|(Shared library)"
export SYSROOT=$(~/x-tools/aarch64-rpizero2w-linux-gnu/bin/aarch64-rpizero2w-linux-gnu-gcc -print-sysroot)
sudo cp -L ${SYSROOT}/lib64/{ld-linux-aarch64.so.1,libm.so.6,libresolv.so.2,libc.so.6} ~/rootfs/lib64/
```
## Size Reduction
We can reduce size of libraries and programs by stripping the binaries of symbol tables
```bash
sudo ~/x-tools/aarch64-rpizero2w-linux-gnu/bin/aarch64-rpizero2w-linux-gnu-strip ~/rootfs/lib64/*
```

## Create device nodes
```bash
cd ~/rootfs
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1
```

## Boot with initramfs
```bash
cd ~/rootfs
find . | cpio -H newc -ov --owner root:root > ../initramfs.cpio
cd ..
gzip initramfs.cpio
~/u-boot/tools/mkimage -A arm64 -O linux -T ramdisk -d initramfs.cpio.gz uRamdisk

# Copy the initramffs to boot partition
sudo cp uRamdisk /media/${USER}/boot/

# clean up
rm uRamdisk initramfs.cpio.gz
```
