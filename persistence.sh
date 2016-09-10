#!/usr/bin/env bash

  USB=/dev/sdc
  ISO=linuxmint-18-cinnamon-64bit.iso
  HOME_LABEL=home-rw
  PERSISTENCE_LABEL=casper-rw
  PERSISTENCE_SIZE_MB=4095     # Max FAT32 file size limit, sorry.
  LIVE_LAST_SECT=12582911      # Last 512-byte sector of 6G LIVE partition
  HOSTNAME=sidrat              # Change to: tardis, for USB3 drive.

configure_grub()
{
echo GRUB configuration goes here.
cat <<EOF >/media/LIVE/boot/grub/grub.cfg
set timeout=30
set pager=1
if [ -s \$prefix/grubenv ]; then
	 load_env
fi
set default="\${saved_entry}"
if [ "\${prev_saved_entry}" ]; then
	set saved_entry="\${prev_saved_entry}"
	save_env saved_entry
	set prev_saved_entry=
	save_env prev_saved_entry
	set boot_once=true
fi
function savedefault {
	if [ -z "\${boot_once}" ]; then
		saved_entry="\${chosen}"
		save_env saved_entry
	fi
}
if loadfont /boot/grub/font.pf2 ; then
	set gfxmode=1024x768,auto
	insmod efi_gop
	insmod efi_uga
	insmod gfxterm
	terminal_output gfxterm
fi
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
menuentry "Linux Mint 18 Cinnamon 64-bit" {
	savedefault
	set gfxpayload=keep
#	linux	/casper/vmlinuz  file=/cdrom/preseed/linuxmint.seed boot=casper iso-scan/filename=\${iso_path} quiet splash --
	linux	/casper/vmlinuz  file=/cdrom/preseed/linuxmint.seed boot=casper iso-scan/filename=\${iso_path} quiet splash noprompt hostname=$HOSTNAME -- persistent
	initrd	/casper/initrd.lz
}
menuentry "Linux Mint 18 Cinnamon 64-bit (rescue)" {
#	linux	/casper/vmlinuz  file=/cdrom/preseed/linuxmint.seed boot=casper xforcevesa iso-scan/filename=\${iso_path} ramdisk_size=1048576 root=/dev/ram rw noapic noacpi nosplash irqpoll --
	linux	/casper/vmlinuz  file=/cdrom/preseed/linuxmint.seed boot=casper xforcevesa iso-scan/filename=\${iso_path} ramdisk_size=1048576 root=/dev/ram rw rescue noacpi nosplash irqpoll noprompt --
	initrd	/casper/initrd.lz
}
menuentry "Windows" {
	insmod part_gpt
	insmod fat
	insmod part_msdos
	insmod ntfs
	if f=/efi/Microsoft/Boot/bootmgfw.efi ; search --file --no-floppy --set=root \$f ; then
		chainloader \$f
	elif f=/bootmgr ; search --file --no-floppy --set=root \$f ; then
		chainloader +1
	else
		echo Windows not found.  Exiting GRUB ...
		sleep 5
		exit
	fi
	savedefault
	clear
	echo Found \$f
	echo Booting Windows on (\$root)
	sleep 5
}
#menuentry "OEM install (for manufacturers)" {
#	set gfxpayload=keep
#	linux	/casper/vmlinuz  file=/cdrom/preseed/linuxmint.seed oem-config/enable=true only-ubiquity boot=casper iso-scan/filename=\${iso_path} quiet splash --
#	initrd	/casper/initrd.lz
#}
menuentry "Check the integrity of the medium" {
	linux	/casper/vmlinuz  boot=casper integrity-check iso-scan/filename=\${iso_path} quiet splash --
	initrd	/casper/initrd.lz
}
menuentry "EXIT" {
	savedefault
	exit
}
EOF
}

passfail()
{
printf '\n'
date +"%F %T"
printf "....: %s\r" "$1"
shift
output="$($* 2>&1)"
status=$?
if [ $status -eq 0 ]
then
  printf "PASS\n"
  [ "$output" != "" ] && echo "$output" | sed 's/^/      /'
else
  printf "FAIL\n"
  [ "$output" != "" ] && echo "$output" | sed 's/^/      /'
  exit $status
fi
}

passwarn()
{
printf '\n'
date +"%F %T"
printf "....: %s\r" "$1"
shift
output="$($* 2>&1)"
status=$?
if [ $status -eq 0 ]
then
  printf "PASS\n"
else
  printf "WARN\n"
fi
[ "$output" != "" ] && echo "$output" | sed 's/^/      /'
}

unmount_USB_partitions()
{
df | grep "^${USB}" \
| while read partition blocks used available used mountpoint
  do
    passfail "Unmounting $partition ($mountpoint)" \
      umount $partition
  done
}

passfail "Got to be root." \
  test "$(whoami)" == "root"

passfail "Ensure LIVE mountpoint (/media/LIVE) is vacant." \
  test ! -d /media/LIVE

passfail "Ensure ISO mountpoint (/media/ISO) is vacant." \
  test ! -d /media/ISO

unmount_USB_partitions

passfail "Clear first 16MB on ${USB}." \
  dd if=/dev/zero of=${USB} bs=1M count=16  # This avoids grub-install error later on

  sleep 10

passfail "Create msdos disk label for ${USB}." \
  parted -s ${USB} mklabel msdos

  sleep 10

passfail "Allocate bootable LIVE partition." \
  parted -s ${USB} unit s mkpart primary fat32 2048 $LIVE_LAST_SECT set 1 boot on

  let align=262144/512
  eval $(parted -s ${USB} unit s print free | awk -F '[ s]*' '
    /Free/ {start=$2; end=$3} ; END {printf "start=%d end=%d",start,end}')
  let start=(start+align-1)/align*align
  let end=(end+1)/align*align-1

  sleep 10

passfail "Allocate home persistence (${HOME_LABEL}) partition." \
  parted -s ${USB} unit s mkpart primary ext2 $start $end

  sleep 10

passfail "Format LIVE partition as FAT32." \
  mkdosfs -F32 -v -n "LIVE" ${USB}1

  sleep 10

unmount_USB_partitions   # Yes, again!

passfail "Create LIVE and ISO mountpoints." \
  mkdir /media/LIVE /media/ISO

passfail "Mount LIVE partition." \
  mount ${USB}1 /media/LIVE

passfail "Allocate root persistence (${PERSISTENCE_LABEL}) file." \
  dd if=/dev/zero of=/media/LIVE/${PERSISTENCE_LABEL} bs=$[1024*1024] count=${PERSISTENCE_SIZE_MB}

passfail "Format root persistence file as EXT2." \
  mke2fs -m 0 -L ${PERSISTENCE_LABEL} /media/LIVE/${PERSISTENCE_LABEL}

passfail "Set max mount count for root persistence." \
  tune2fs -c 1 /media/LIVE/${PERSISTENCE_LABEL}

passfail "Format home persistence partition as EXT2." \
  mke2fs -m 0 -L ${HOME_LABEL} ${USB}2

passfail "Set max mount count for home persistence." \
  tune2fs -c 1 ${USB}2

passfail "Mount ISO image (${ISO})." \
  mount -o loop ${ISO} /media/ISO

pushd /media/ISO >/dev/null

  passwarn "Copy ISO files to LIVE partition." \
    cp -ia . /media/LIVE

popd >/dev/null

passfail "Install GRUB." \
  grub-install --no-floppy --root-directory=/media/LIVE ${USB}

if [ ! -f /media/LIVE/boot/grub/grub.cfg.stock ]
then
  passwarn "Backup stock GRUB configuration." \
    cp -vp /media/LIVE/boot/grub/grub.cfg /media/LIVE/boot/grub/grub.cfg.stock
fi

passfail "Customize GRUB configuration." \
  configure_grub

passfail "Unmount ISO image (${ISO})." \
  umount /media/ISO

passfail "Remove ISO mountpoint (/media/ISO)." \
  rmdir /media/ISO

passfail "Unmount LIVE partition." \
  umount /media/LIVE

passfail "Remove LIVE mountpoint (/media/LIVE)." \
  rmdir /media/LIVE

exit 0
