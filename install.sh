#!/bin/bash

# Setup variables here.
encryption_passphrase="password"
root_password="password"
user_password="password"
hostname="host"
user_name="test"
continent_city="Atlanta"
swap_size="8"

# Setup bash colors here
RESTORE='\033[0m'
RED='\033[00;31m'
GREEN='\033[00;32m'

# Check Internet connection in order: ipv4 --> dns --> 
if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
  echo "IPv4 is up"
else
  echo -e "$RED IPv4 is down $RESTORE"  # end script here?  or prompt for connection?
fi
if ping -q -c 1 -W 1 google.com >/dev/null; then
  echo "The network is up"
else
  echo -e "$RED The network is down $RESTORE" # end script here?  or prompt for connection?
fi

# need to update the clock first.
echo "Updating system clock"
timedatectl set-ntp true

# TODO:
# check to see if global variables are emtpy.  If they are prompt for info
[  -z "$encryption_passphrase" ] && echo "Empty: Yes" || echo "Empty: No"
[  -z "$root_password" ] && echo "Empty: Yes" || echo "Empty: No"
[  -z "$user_password" ] && echo "Empty: Yes" || echo "Empty: No"
[  -z "$hostname" ] && echo "Empty: Yes" || echo "Empty: No"
[  -z "$user_name" ] && echo "Empty: Yes" || echo "Empty: No"
[  -z "$continent_city" ] && echo "Empty: Yes" || echo "Empty: No"
[  -z "$swap_size" ] && echo "Empty: Yes" || echo "Empty: No"

# TODO: Does this matter to install?  
# UEFI vs BIOS - consult your mobo


# Query for disk to install to
lsblk
echo -e "$RED Selecting this will erase everything from the drive $RESTORE"
echo -e "$GREEN Enter the full /dev/sdX - not only sdX $RESTORE"
read -p "Enter disk to install to: "  DISK
echo -e "$RED wiping: $DISK, are you sure?!?! $RESTORE"
read -p "[Y/y/n]" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  exit 1
fi
# if the script hasn't imploded run shred on the disk
# gotta go fast - single pass with /dev/urandom
shred -v --random-source=/dev/urandom -n1 $DISK

# The sed script strips off all the comments so that we can 
# document what we're doing in-line with the actual commands
# Note that a blank line (commented as "defualt" will send a empty
# line terminated with a newline to take the fdisk default.
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $DISK
  g # clear the in memory partition table - create new empty GPT partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +100M # 100 MB boot parttion
  n # new partition
  2 # partion number 2
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  1 # bootable partition is partition 1 -- /dev/sda1
  p # print the in-memory partition table
  w # write the partition table
EOF
#TODO: add swap space partition for later sleep support

# create variables for the partitions
DISK1="$DISK""1"
DISK2="$DISK""2"

# Throws an error message saying no space left.  I think it's recommended not to do this anymore. 
clea#echo "Zeroing partitions"
#cat /dev/zero > /dev/$DISK1
#cat /dev/zero > /dev/$DISK2

echo "Building EFI filesystem"
yes | mkfs.fat -F32 $DISK1

# temp pause for debugging
fdisk -l
read -p "Pause, press enter to continue"

echo "Setting up cryptographic volume"
printf "%s" "$encryption_passphrase" | cryptsetup -c aes-xts-plain64 -h sha512 -s 512 --use-random --type luks2 --label LVMPART luksFormat /dev/$DISK2
printf "%s" "$encryption_passphrase" | cryptsetup luksOpen /dev/$DISK2 cryptoVols

echo "Setting up LVM"
pvcreate /dev/mapper/cryptoVols
vgcreate Arch /dev/mapper/cryptoVols
lvcreate -L +"$swap_size"GB Arch -n swap
lvcreate -l +100%FREE Arch -n root

echo "Building filesystems for root and swap"
yes | mkswap /dev/mapper/Arch-swap
yes | mkfs.ext4 /dev/mapper/Arch-root

echo "Mounting root/boot and enabling swap"
mount /dev/mapper/Arch-root /mnt
mkdir /mnt/boot
mount /dev/$DISK1 /mnt/boot
swapon /dev/mapper/Arch-swap

# temp pause for debugging
fdisk -l
read -p "Pause, press enter to continue"

echo "Installing Arch Linux"
yes '' | pacstrap /mnt base base-devel intel-ucode networkmanager wget reflector

echo "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "Configuring new system"
arch-chroot /mnt /bin/bash <<EOF

echo "Setting system clock"
ln -fs /usr/share/zoneinfo/$continent_city /etc/localtime
hwclock --systohc --localtime

echo "Setting locales"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
locale-gen

echo "Setting hostname"
echo $hostname > /etc/hostname

echo "Setting root password"
echo -en "$root_password\n$root_password" | passwd

echo "Creating new user"
useradd -m -G wheel -s /bin/bash $user_name
echo -en "$user_password\n$user_password" | passwd $user_name

echo "Generating initramfs"
sed -i 's/^HOOKS.*/HOOKS=(base udev keyboard autodetect modconf block keymap encrypt lvm2 resume filesystems fsck)/' /etc/mkinitcpio.conf
sed -i 's/^MODULES.*/MODULES=(ext4 intel_agp i915)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

echo "Setting up systemd-boot"
bootctl --path=/boot install
mkdir -p /boot/loader/
touch /boot/loader/loader.conf
tee -a /boot/loader/loader.conf << END
default arch
timeout 0
editor 0
END
mkdir -p /boot/loader/entries/
touch /boot/loader/entries/arch.conf
tee -a /boot/loader/entries/arch.conf << END
title ArchLinux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options cryptdevice=LABEL=LVMPART:cryptoVols root=/dev/mapper/Arch-root resume=/dev/mapper/Arch-swap quiet rw
END

echo "Setting up Pacman hook for automatic systemd-boot updates"
mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/systemd-boot.hook
tee -a /etc/pacman.d/hooks/systemd-boot.hook << END
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd
[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
END

echo "Enabling autologin"
mkdir -p  /etc/systemd/system/getty@tty1.service.d/
touch /etc/systemd/system/getty@tty1.service.d/override.conf
tee -a /etc/systemd/system/getty@tty1.service.d/override.conf << END
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $user_name --noclear %I $TERM
END
echo "Updating mirrors list"
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.BAK
reflector --latest 200 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
touch /etc/pacman.d/hooks/mirrors-update.hook
tee -a /etc/pacman.d/hooks/mirrors-update.hook << END
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist
[Action]
Description = Updating pacman-mirrorlist with reflector
When = PostTransaction
Depends = reflector
Exec = /bin/sh -c "reflector --latest 200 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
END

echo "Enabling periodic TRIM"
systemctl enable fstrim.timer

echo "Enabling NetworkManager"
systemctl enable NetworkManager

echo "Adding user as a sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
EOF

umount -R /mnt
swapoff -a

echo "ArchLinux is ready. You can reboot now!"
