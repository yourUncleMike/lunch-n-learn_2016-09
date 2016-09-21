#!/usr/bin/env bash

  USB1=${1:-/dev/sdb}
  USB2=${2:-/dev/sdc}
  HOME_LABEL=home-rw
  PERSISTENCE_LABEL=casper-rw
  PERSISTENCE_SIZE_MB=4095     # Max FAT32 file size limit, sorry.
  LIVE_LAST_SECT=12582911      # Last 512-byte sector of 6G LIVE partition

passfail()
{
printf '\n'
date +"%F %T"
printf "....: %s\r" "$1"
shift
if output="$($* 2>&1)"
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
if output="$($* 2>&1)"
then
  printf "PASS\n"
else
  printf "WARN\n"
fi
[ "$output" != "" ] && echo "$output" | sed 's/^/      /'
}

unmount_USB_partitions()
{
USBs="$(echo $* | sed 's/\//\\\//g; s/  */|/g')"
df | awk '/^('"$USBs"')/ && $6 != "/cdrom" {print $6}' \
| while read mountpoint
  do
    passfail "Unmounting $partition ($mountpoint)" \
      umount $mountpoint
  done
}

check_singleuser()
{
test "$(runlevel)" == 'N 1'
}

passfail "Got to be root." \
  test "$(whoami)" == "root"

passfail "Got to be at single-user." \
  check_singleuser

for dir in CASPER1 HOME1 CASPER2 HOME2 LIVE2
do
  passfail "Ensure $dir mountpoint (/media/$dir) is vacant." \
    test ! -d /media/$dir
  passfail "Create $dir mountpoint." \
    mkdir /media/$dir
done

unmount_USB_partitions $USB1 $USB2

passfail "Clear first 16MB on ${USB2}." \
  dd if=/dev/zero of=${USB2} bs=1M count=16  # This avoids grub-install error later on

  sync ; sleep 10

passfail "Create msdos disk label for ${USB2}." \
  parted -s ${USB2} mklabel msdos

  sync ; sleep 10

passfail "Allocate bootable LIVE2 partition." \
  parted -s ${USB2} unit s mkpart primary fat32 2048 $LIVE_LAST_SECT set 1 boot on

  let align=262144/512
  eval $(parted -s ${USB2} unit s print free | awk -F '[ s]*' '
    /Free/ {start=$2; end=$3} ; END {printf "start=%d end=%d",start,end}')
  let start=(start+align-1)/align*align
  let end=(end+1)/align*align-1

  sync ; sleep 10

passfail "Allocate HOME2 persistence (${HOME_LABEL}) partition." \
  parted -s ${USB2} unit s mkpart primary ext4 $start $end

  sync ; sleep 10

passfail "Format LIVE2 partition as FAT32." \
  mkdosfs -F32 -v -n "LIVE" ${USB2}1

passfail "Format HOME2 persistence partition as EXT4." \
  mkfs.ext4 -m 0 -O '^has_journal' -L ${HOME_LABEL} ${USB2}2

  sync ; sleep 10

unmount_USB_partitions $USB2

passfail "Mount CASPER1 persistence partition." \
  mount -o ro /cdrom/casper-rw /media/CASPER1

passfail "Mount LIVE2 partition." \
  mount ${USB2}1 /media/LIVE2

passfail "Allocate root persistence (${PERSISTENCE_LABEL}) file." \
  dd if=/dev/zero of=/media/LIVE2/${PERSISTENCE_LABEL} bs=$[1024*1024] count=${PERSISTENCE_SIZE_MB}

passfail "Format CASPER2 persistence file as EXT4." \
  mkfs.ext4 -m 0 -O '^has_journal' -L ${PERSISTENCE_LABEL} /media/LIVE2/${PERSISTENCE_LABEL}

passfail "Mount CASPER2 persistence partition." \
  mount /media/LIVE2/casper-rw /media/CASPER2

passwarn "Clone casper-rw files." \
  rsync -aAHX /media/CASPER1/ /media/CASPER2

passwarn "Clone /cdrom files." \
  rsync -rlt --exclude casper-rw  /cdrom/  /media/LIVE2

passfail "Mount HOME2 partition." \
  mount ${USB2}2 /media/HOME2

passfail "Mount HOME1 partition." \
  mount ${USB1}2 /media/HOME1

passwarn "Clone home-rw files." \
  rsync -aAHX  /media/HOME1/  /media/HOME2

passfail "Install GRUB." \
  grub-install --no-floppy --root-directory=/media/LIVE2 ${USB2}

for dir in CASPER1 HOME1 CASPER2 HOME2 LIVE2
do
  passwarn "Unmount $dir partition." \
    umount /media/$dir
  passwarn "Remove $dir mountpoint." \
    rmdir /media/$dir
done
