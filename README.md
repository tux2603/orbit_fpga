# Orbit FPGA

Orbital determination and burn optimization on the PYNQ-Z2 FPGA board. Interfaces with Kerbal Space Program (KSP) via the kRPC mod to serve as the back-end physics engine.

## Compilation and Uploading

These instructions assume that you have Vivado and PetaLinux installed on your system and that you have a PetaLinux project already initialized.

1. Build the project using Vivado and generate the bitstream.
2. Export your hardware design from Vivado as an XSA file.
3. Copy the XSA file to WSL2 (or any Linux environment).
4. Initialize the petalinux development environment `source /tools/Xilinx/PetaLinux/2025.1/settings.sh`.
5. Import the new XSA file into your petalinux project using `petalinux-config --get-hw-description=<path_to_xsa>`.
6. Build the petalinux project using `petalinux-build`.
7. Package the boot image using `petalinux-package --boot --fsbl images/linux/zynq_fsbl.elf --fpga images/linux/system.bit --u-boot`.
8. Create the SD card image using `petalinux-package --wic --bootfiles "BOOT.BIN image.ub boot.scr" --rootfs-file images/linux/rootfs.tar.gz`.
9. Copy the resulting SD card image (located at `images/linux/petalinux-sdimage.wic`) to your SD card and insert it into the PYNQ-Z2 board.
10. Power on the board and connect to it via SSH or serial console.

## Adding a new driver to petalinux

1. 

