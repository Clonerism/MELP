# Add a toolchain created using CrosstoolNG to your path
# and export ARCH and CROSS_COMPILE variables ready to 
# compile U-Boot, Linux, Busybox and anything else using
# the Kconfig/Kbuild scripts

# Saeid Haghighipour, saeid.haghighi@sharif.edu

PATH=$PATH:~/x-tools/aarch64-rpizero2w-linux-gnu/bin
export CROSS_COMPILE=aarch64-rpizero2w-linux-gnu-
export ARCH=arm64
