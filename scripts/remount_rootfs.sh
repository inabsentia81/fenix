#!/bin/bash

set -e -o pipefail

## Parameters
source config/config

## Board configuraions
source ${BOARD_CONFIG}/${KHADAS_BOARD}.conf

## Functions
source config/functions/functions

########################################################################

remount_rootfs() {
	cd ${ROOT}

	trap cleanup INT EXIT TERM

	IMAGE_LINUX_LOADADDR="0x1080000"
	IMAGE_LINUX_VERSION=`head -n 1 $LINUX_DIR/include/config/kernel.release | xargs echo -n`

	if [ "$INSTALL_TYPE" == "SD-USB" ]; then
		IMAGE_LOOP_DEV="$(sudo losetup --show -f ${BUILD_IMAGES}/${IMAGE_FILE_NAME})"
		IMAGE_LOOP_DEV_BOOT="${IMAGE_LOOP_DEV}p1"
		IMAGE_LOOP_DEV_ROOTFS="${IMAGE_LOOP_DEV}p2"
		sudo partprobe "${IMAGE_LOOP_DEV}"
		echo "Mountng ${IMAGE_LOOP_DEV_ROOTFS}..."
		sudo mount -o loop "${IMAGE_LOOP_DEV_ROOTFS}" $ROOTFS || {
			sudo sync
			error_msg "Failed to mount $IMAGE_LOOP_DEV_ROOTFS!"

			return -1
		}
		echo "Mount ${IMAGE_LOOP_DEV_ROOTFS} on $ROOTFS OK."
		echo "Mounting ${IMAGE_LOOP_DEV_BOOT}..."
		sudo mount -o loop "${IMAGE_LOOP_DEV_BOOT}" $ROOTFS/boot || {
			error_msg "Failed to mount $IMAGE_LOOP_DEV_BOOT!"
			sudo sync
			sudo umount $ROOTFS

			return -1
		}
		echo "Mount ${IMAGE_LOOP_DEV_BOOT} on $ROOTFS/boot OK."
	elif [ "$INSTALL_TYPE" == "EMMC" ]; then
		echo "Mounting rootfs.img..."
		sudo mount -o loop ${BUILD_IMAGES}/rootfs.img $ROOTFS || {
			error_msg "Failed to mount rootfs.img!"

			return -1
		}
		echo "Mount ${BUILD_IMAGES}/rootfs.img on $ROOTFS/ OK."
	fi

	## [Optional] Mirrors for ubuntu-ports
	if [ -f .khadas-build ]; then
		echo "Using ustc mirrors..."
		sudo cp -a $ROOTFS/etc/apt/sources.list $ROOTFS/etc/apt/sources.list.orig
		sudo sed -i "s/http:\/\/ports.ubuntu.com\/ubuntu-ports\//http:\/\/mirrors.ustc.edu.cn\/ubuntu-ports\//g" $ROOTFS/etc/apt/sources.list
	fi

	# Hack for deb builder. To pack what's missing in headers pack.
	cp archives/patches/misc/headers-debian-byteshift.patch /tmp

	# Different packaging for 4.3+
	if linux-version compare $IMAGE_LINUX_VERSION ge 4.3; then
		KERNEL_PACKING="bindeb-pkg"
	else
		KERNEL_PACKING="deb-pkg"
	fi

	# Build linux debs
	build_linux_debs

	# linux version
	echo $IMAGE_LINUX_VERSION > $BUILD_IMAGES/linux-version
	sudo cp -r $BUILD_IMAGES/linux-version $ROOTFS/

	## firstboot initialization: for 'ROOTFS' partition resize
	if [ "$INSTALL_TYPE" == "EMMC" ]; then
		sudo touch $ROOTFS/etc/default/FIRSTBOOT
	fi

	## script executing on chroot
	sudo cp -r scripts/chroot-scripts/RUNME_REMOUNT.sh $ROOTFS/

	## Prepare chroot
	prepare_chroot

	mount_chroot "$ROOTFS"

	while true; do
		read -n1 -p $'\n(A)utorun script, (M)anual chroot or (Q)uit? [a/m/q]' answer
		case $answer in
			[Aa]* )
				echo -e "\nAutorun script."
				sudo chroot $ROOTFS/ bash "/RUNME_REMOUNT.sh" $UBUNTU $INSTALL_TYPE
				break;;
			[Mm]* )
				echo -e "\n\nNOTE: YOU ARE NOW IN THE VIRTUAL TARGET, SETUP ANYTHING YOU WANT."
				echo -e "      TYPE 'exit' TO CONTINUE IF FINISHED.\n"
				sudo chroot $ROOTFS/
				break;;
			[Qq]* )
				echo -e "\nQuit."
				break;;
			* )
				echo -e "\n(A)utorun script, (M)anual chroot or (Q)uit? [a/m/q]"
		esac
	done

	## Unmount to get the rootfs.img
	sudo sync
	umount_chroot "$ROOTFS"

	if [ "$INSTALL_TYPE" == "SD-USB" ]; then
		sudo umount $ROOTFS/boot
		sudo losetup -d "${IMAGE_LOOP_DEV}"
	fi
	sudo umount $ROOTFS

	trap - INT EXIT TERM

	return 0
}


########################################################
remount_rootfs

echo -e "\nDone."
echo -e "\n`date`"
