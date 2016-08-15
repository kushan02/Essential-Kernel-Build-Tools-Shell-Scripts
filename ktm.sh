#!/bin/bash

LANG=C

# location
if [ "${1}" != "" ]; then
	export KERNELDIR=`readlink -f ${1}`;
else
	export KERNELDIR=`readlink -f .`;
fi;

export PARENT_DIR=`readlink -f ..`
export INITRAMFS_TMP=/tmp/initramfs_source;
export INITRAMFS_SOURCE=`readlink -f ..`/Ramdisk-alu
export PACKAGEDIR=$KERNELDIR/BUILD_OUTPUT
export KERNEL_CONFIG=kushan_defconfig;

chmod -R 777 /tmp;

time_start=$(date +%s.%N)

# check xml-config for "STweaks"-app
#XML2CHECK="${INITRAMFS_SOURCE}/res/customconfig/customconfig.xml";
#xmllint --noout $XML2CHECK;
#if [ $? == 1 ]; then
#	echo "xml-Error: $XML2CHECK";
#	exit 1;
#fi;

echo "Setup Package Directory"
mkdir -p $PACKAGEDIR/system/lib/modules

if [ -d $INITRAMFS_TMP ]; then
	echo "removing old temp initramfs_source";
	rm -rf $INITRAMFS_TMP;
fi;

# copy new config
cp $KERNELDIR/.config $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG;

# remove all old modules before compile
for i in `find $KERNELDIR/ -name "*.ko"`; do
	rm -f $i;
done;
for i in `find $PACKAGEDIR/system/lib/modules/ -name "*.ko"`; do
	rm -f $i;
done;

# copy initramfs files to tmp directory
cp -ax $INITRAMFS_SOURCE $INITRAMFS_TMP;

# clear git repository from tmp-initramfs
if [ -d $INITRAMFS_TMP/.git ]; then
	rm -rf $INITRAMFS_TMP/.git;
fi;

# clear mercurial repository from tmp-initramfs
if [ -d $INITRAMFS_TMP/.hg ]; then
	rm -rf $INITRAMFS_TMP/.hg;
fi;

# remove empty directory placeholders from tmp-initramfs
for i in `find $INITRAMFS_TMP -name EMPTY_DIRECTORY`; do
	rm -f $i;
done;

# copy config
if [ ! -f $KERNELDIR/.config ]; then
	cp $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG $KERNELDIR/.config;
fi;

# read config
. $KERNELDIR/.config;

# get version from config
GETVER=`grep 'Alucard-*-V' kernel_version |sed 's/Alucard-//g' | sed 's/.*".//g' | sed 's/-A.*//g'`;

echo "Remove old zImage"
# remove previous zImage files
if [ -e $PACKAGEDIR/boot.img ]; then
	rm $PACKAGEDIR/boot.img;
fi;

if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	rm $KERNELDIR/arch/arm/boot/zImage;
fi;

HOST_CHECK=`uname -n`
NAMBEROFCPUS=$(expr `grep processor /proc/cpuinfo | wc -l` + 1);
echo $HOST_CHECK

echo "Making kernel";
time make ARCH=arm CROSS_COMPILE=/home/kushan/toolchain/linaro/bin/arm-cortex_a15-linux-gnueabihf- CC='/home/kushan/toolchain/linaro/bin/arm-cortex_a15-linux-gnueabihf-gcc --sysroot=/home/kushan/toolchain/linaro/arm-cortex_a15-linux-gnueabihf/sysroot/' zImage -j ${NAMBEROFCPUS}
stat "$KERNELDIR"/arch/arm/boot/zImage || exit 1;

echo "Compiling Modules............"
time make ARCH=arm CROSS_COMPILE=/home/kushan/toolchain/linaro//bin/arm-cortex_a15-linux-gnueabihf- CC='/home/kushan/toolchain/linaro/bin/arm-cortex_a15-linux-gnueabihf-gcc --sysroot=/home/kushan/toolchain/linaro/arm-cortex_a15-linux-gnueabihf/sysroot/' modules -j ${NR_CPUS} || exit 1

echo "Copy modules to Package"
for i in `find $KERNELDIR -name '*.ko'`; do
	cp -av $i $PACKAGEDIR/system/lib/modules/;
done;

chmod 644 $PACKAGEDIR/system/lib/modules/*;

if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	echo "Copy zImage to Package"
	cp arch/arm/boot/zImage $PACKAGEDIR/zImage

	# strip not needed debugs from modules.
	/home/kushan/toolchain/linaro/bin/arm-cortex_a15-linux-gnueabihf-strip --strip-unneeded $PACKAGEDIR/system/lib/modules/* 2>/dev/null
	/home/kushan/toolchain/linaro/bin/arm-cortex_a15-linux-gnueabihf-strip --strip-debug $PACKAGEDIR/system/lib/modules/* 2>/dev/null

	echo "Make boot.img"
	./mkbootfs $INITRAMFS_TMP | gzip > $PACKAGEDIR/ramdisk.gz
	cmd_line="console=ttyHSL0,115200,n8 androidboot.hardware=qcom user_debug=31 ehci-hcd.park=3 enforcing=0 selinux=1"
	./mkbootimg --cmdline "$cmd_line" --kernel $PACKAGEDIR/zImage --ramdisk $PACKAGEDIR/ramdisk.gz --base 0x80200000 --pagesize 2048 --ramdisk_offset 0x02000000 --output $PACKAGEDIR/boot.img
	cd $PACKAGEDIR

	if [ -e ramdisk.gz ]; then
		rm ramdisk.gz;
	fi;

	if [ -e zImage ]; then
		rm zImage;
	fi;

	echo "Remove old Package Zip Files"
	for i in `find $PACKAGEDIR/ -name '*.zip'`; do
	 rm $i;
	done;

	FILENAME=Kernel-Alucard-${GETVER}-`date +"[%H-%M]-[%d-%m]-AOSPV4-EUR-MM6.0-SGIV-PWR-CORE"`.zip
	zip -r $FILENAME .;

	time_end=$(date +%s.%N)
	echo -e "${BLDYLW}Total time elapsed: ${TCTCLR}${TXTGRN}$(echo "($time_end - $time_start) / 60"|bc ) ${TXTYLW}minutes${TXTGRN} ($(echo "$time_end - $time_start"|bc ) ${TXTYLW}seconds) ${TXTCLR}"

	FILESIZE=$(stat -c%s "$FILENAME")
	echo "Size of $FILENAME = $FILESIZE bytes."
	
	cd $KERNELDIR
else
	echo "KERNEL DID NOT BUILD! no zImage exist"
fi;

