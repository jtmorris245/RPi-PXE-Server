#!/bin/bash
# v2016-07-22
#(Made it only download a single image - http://www.ultimatebootcd.com/ )
######################################################################
echo -e "\e[32msetup variables\e[0m";
NFS=/nfs
TFTP=/tftp
ISO=/iso
SRC_MOUNT=/media/server
SRC_ROOT=$SRC_MOUNT$TFTP
SRC_ISO=$SRC_ROOT$ISO
SRC_NFS=$SRC_ROOT$NFS
DST_ROOT=/srv$TFTP
DST_ISO=$DST_ROOT$ISO
DST_NFS=$DST_ROOT$NFS
IP_LOCAL=$(echo $(hostname -I) | sed 's/ //g')
IP_LOCAL_=$(echo $IP_LOCAL | grep -E -o "([0-9]{1,3}[\.]){3}")
IP_LOCAL_0=$(echo $(echo $IP_LOCAL_)0)
IP_LOCAL_START=$(echo $(echo $IP_LOCAL_)200)
IP_LOCAL_END=$(echo $(echo $IP_LOCAL_)229)
IP_LOCAL_255=$(echo $(echo $IP_LOCAL_)255)
IP_ROUTER=$(grep "nameserver" /etc/resolv.conf | sed -r "s/nameserver([ ]{1,})//g")
IP_SUB=255.255.255.0

######################################################################

UBCD_URL=http://mirror.sysadminguide.net/ubcd/ubcd536.iso

UBCD=ubcd


######################################################################
handle_iso() {
	[ -d "$DST_ISO/" ] || sudo mkdir -p $DST_ISO/;
	[ -d "$DST_NFS/" ] || sudo mkdir -p $DST_NFS/;

	sudo exportfs -u *:$DST_NFS/$1 2> /dev/null;
	sudo umount -f $DST_ISO/$1 2> /dev/null;

	[ "$2" == "" ] && {
		! [ -f "$DST_ISO/$1.iso" ] && {
			echo -e "\e[32m($1) copy iso from usb-stick for pxe\e[0m";
			sudo rm -f $DST_ISO/$1.url;
			sudo cp -pv $SRC_ISO/$1.iso $DST_ISO;
			sudo cp -pv $SRC_ISO/$1.url $DST_ISO;
		};
	};

	[ "$2" != "" ] && {
		! grep -q "$2" $DST_ISO/$1.url 2> /dev/null && grep -q "$2" $SRC_ISO/$1.url 2> /dev/null && {
			echo -e "\e[32m($1) copy iso from usb-stick for pxe\e[0m";
			sudo rm -f $DST_ISO/$1.url;
			sudo cp -pv $SRC_ISO/$1.iso $DST_ISO;
			sudo cp -pv $SRC_ISO/$1.url $DST_ISO;
		};

		! [ -f "$DST_ISO/$1.iso" ] || ! grep -q "$2" $DST_ISO/$1.url 2> /dev/null && {
			echo -e "\e[32m($1) download iso image for pxe\e[0m";
			sudo rm -f $DST_ISO/$1.iso;
			sudo rm -f $DST_ISO/$1.url;
			sudo wget -O $DST_ISO/$1.iso $2;
		};
	};


	sudo sh -c "echo '$2' > $DST_ISO/$1.url";
	sudo touch -r $DST_ISO/$1.iso $DST_ISO/$1.url;

	[ -d "$DST_NFS/$1" ] || {
		echo -e "\e[32m($1) create nfs folder for pxe\e[0m";
		sudo mkdir -p $DST_NFS/$1;
	};

	grep -q "$DST_NFS/$1" /etc/fstab || {
		echo -e "\e[32m($1) add iso image to fstab for pxe\e[0m";
		sudo sh -c "echo '$DST_ISO/$1.iso  $DST_NFS/$1  auto  loop,ro  0  0' >> /etc/fstab";
	};
	sudo mount -a;

	grep -q "$DST_NFS/$1" /etc/exports || {
		echo -e "\e[32m($1) add nfs folder to exports for pxe\e[0m";
		sudo sh -c "echo '$DST_NFS/$1  *(ro,no_subtree_check,async,root_squash)' >> /etc/exports";
	};
	sudo exportfs -a;
}


######################################################################
sudo mkdir -p $DST_ROOT;
sudo mkdir -p $DST_ISO;


######################################################################
grep -q tftp /etc/samba/smb.conf 2> /dev/null || ( \
echo -e "\e[32msetup samba\e[0m";
sudo sed -i /etc/samba/smb.conf -n -e "1,/#======================= Share Definitions =======================/p";
sudo sh -c "echo '
## inserted by install-server.sh
[tftp]
  comment = TFTP + PXE
  path = $DST_ROOT/
  public = yes
  only guest = yes
  browseable = yes
  read only = no
  writeable = yes
  create mask = 0644
  directory mask = 0755
  force create mask = 0644
  force directory mask = 0755
  force user = root
  force group = root

[media]
  comment = Media
  path = $SRC_MOUNT/
  public = yes
  only guest = yes
  browseable = yes
  read only = no
  writeable = yes
  create mask = 0644
  directory mask = 0755
  force create mask = 0644
  force directory mask = 0755
  force user = root
  force group = root
' >> /etc/samba/smb.conf"
#sudo service samba restart;
)


######################################################################
grep -q max_loop /boot/cmdline.txt 2> /dev/null || {
	echo -e "\e[32msetup cmdline.txt for more loop devices\e[0m";
	sudo sed -i '1 s/$/ max_loop=64/' /boot/cmdline.txt;
}
######################################################################
handle_iso  $UBCD        $UBCD_URL;

######################################################################
echo -e "\e[32menable port mapping and necessary services\e[0m";
sudo service nfs-common stop
sudo service nfs-kernel-server stop
sudo service rpcbind stop
sudo update-rc.d rpcbind enable
sudo update-rc.d nfs-common enable
sudo update-rc.d nfs-kernel-server enable
sudo update-rc.d rpcbind defaults
sudo service rpcbind restart
sudo service nfs-kernel-server restart
# fix for systemd dependency cycle
grep -q nfs-kernel-server /etc/rc.local || sudo sed /etc/rc.local -i -e "s/^exit 0$/sudo service nfs-kernel-server restart &\n\nexit 0/";


######################################################################
echo -e "\e[32mcopy win-pe stuff\e[0m";
[ -f "$DST_ROOT/pxeboot.0" ]   || sudo cp -pRv $SRC_ROOT/pxeboot.0    $DST_ROOT/
[ -f "$DST_ROOT/bootmgr.exe" ] || sudo cp -pRv $SRC_ROOT/bootmgr.exe  $DST_ROOT/
[ -d "$DST_ROOT/boot" ]        || sudo cp -pRv $SRC_ROOT/boot         $DST_ROOT/
[ -d "$DST_ROOT/sources" ]     || sudo ln -s $DST_NFS/$WIN_PE_X86/sources/  $DST_ROOT/sources


######################################################################
echo -e "\e[32msetup sys menu for pxe\e[0m";
[ -f "$DST_ROOT/pxelinux.0" ]   || sudo ln -s /usr/lib/PXELINUX/pxelinux.0                 $DST_ROOT/
[ -f "$DST_ROOT/ldlinux.c32" ]  || sudo ln -s /usr/lib/syslinux/modules/bios/ldlinux.c32   $DST_ROOT/
[ -f "$DST_ROOT/vesamenu.c32" ] || sudo ln -s /usr/lib/syslinux/modules/bios/vesamenu.c32  $DST_ROOT/
[ -f "$DST_ROOT/libcom32.c32" ] || sudo ln -s /usr/lib/syslinux/modules/bios/libcom32.c32  $DST_ROOT/
[ -f "$DST_ROOT/libutil.c32" ]  || sudo ln -s /usr/lib/syslinux/modules/bios/libutil.c32   $DST_ROOT/
[ -f "$DST_ROOT/memdisk" ]      || sudo ln -s /usr/lib/syslinux/memdisk                    $DST_ROOT/

[ -d "$DST_ROOT/pxelinux.cfg" ] || sudo mkdir -p $DST_ROOT/pxelinux.cfg
[ -d "$DST_ROOT/pxelinux.cfg" ] && sudo sh -c "echo '########################################
# /srv/tftp/pxelinux.cfg/default


DEFAULT /vesamenu.c32 
TIMEOUT 600
ONTIMEOUT Boot Local
PROMPT 0
NOESCAPE 1
ALLOWOPTIONS 1

menu hshift 5
menu width 59

menu title PXE Boot Menu

menu color title        * #FFFFFFFF *
menu color border       * #00000000 #00000000 none
menu color sel          * #ffffffff #76a1d0ff *
menu color hotsel       1;7;37;40 #ffffffff #76a1d0ff *
menu color tabmsg       * #ffffffff #00000000 *
menu color help         37;40 #ffdddd00 #00000000 none
menu vshift 2
menu rows 20
menu helpmsgrow 25
# The command line must be at least one line from the bottom.
menu cmdlinerow 26
menu timeoutrow 26
menu tabmsgrow 28
menu tabmsg Press ENTER to boot or TAB to edit a menu entry


LABEL Boot Local
    localboot 0
    TEXT HELP
        Boot to local hard disk
    ENDTEXT

' > $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_ROOT/pxeboot.0" ] && sudo sh -c "echo '########################################
LABEL Windows PE x86 (PXE)
    PXE /pxeboot.0
    TEXT HELP
        Boot to Windows PE 32bit
        en
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_ISO/$WIN_PE_X86.iso" ] && sudo sh -c "echo '########################################
LABEL Windows PE x86 (ISO)
    KERNEL /memdisk
    APPEND iso
    INITRD $ISO/$WIN_PE_X86.iso
    TEXT HELP
        Boot to Windows PE 32bit ISO ~400MB
        en
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$UBUNTU_X64/casper/vmlinuz.efi" ] && sudo sh -c "echo '########################################
LABEL Ubuntu x64
    KERNEL $NFS/$UBUNTU_X64/casper/vmlinuz.efi
    APPEND initrd=$NFS/$UBUNTU_X64/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$UBUNTU_X64  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to Ubuntu x64 Live
        k:de, l:de/en
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$UBUNTU_X86/casper/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL Ubuntu x86
    KERNEL $NFS/$UBUNTU_X86/casper/vmlinuz
    APPEND initrd=$NFS/$UBUNTU_X86/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$UBUNTU_X86  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to Ubuntu x86 Live
        k:de, l:de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$UBCD/pmagic/bzImage" ] && sudo sh -c "echo '########################################
LABEL UBCD
    KERNEL $NFS/$UBCD/pmagic/bzImage
    APPEND initrd=$NFS/$UBCD/pmagic/bzImage  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$UBCD
    TEXT HELP
        Boot to Ubuntu LTS x64 Live
        k:de, l:de/en
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$UBUNTU_LTS_X86/casper/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL Ubuntu LTS x86
    KERNEL $NFS/$UBUNTU_LTS_X86/casper/vmlinuz
    APPEND initrd=$NFS/$UBUNTU_LTS_X86/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$UBUNTU_LTS_X86  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to Ubuntu LTS x86 Live
        k:de, l:de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$UBUNTU_NONPAE/casper/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL  Ubuntu non-PAE x86
    KERNEL $NFS/$UBUNTU_NONPAE/casper/vmlinuz
    APPEND initrd=$NFS/$UBUNTU_NONPAE/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$UBUNTU_NONPAE  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to Ubuntu non-PAE x86 Live
        k:de, l:de/en
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$DEBIAN_X64/live/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL Debian x64
    KERNEL $NFS/$DEBIAN_X64/live/vmlinuz
    APPEND initrd=$NFS/$DEBIAN_X64/live/initrd.img  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$DEBIAN_X64  boot=live  config  --  locales=de_DE  keyboard-layouts=de
    # siehe ...
    # /lib/live/config/0050-locales                 locales=de_DE
    # /lib/live/config/0160-keyboard-configuration  keyboard-layouts=de
    # /lib/live/config/0070-tzdata                  timezone=Europe/Berlin
    TEXT HELP
        Boot to Debian x64 Live LXDE
        k:en, l:de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$DEBIAN_X86/live/vmlinuz2" ] && sudo sh -c "echo '########################################
LABEL Debian x86
    KERNEL $NFS/$DEBIAN_X86/live/vmlinuz2
    APPEND initrd=$NFS/$DEBIAN_X86/live/initrd2.img  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$DEBIAN_X86  boot=live  config  --  locales=de_DE  keyboard-layouts=de
    # siehe ...
    # /lib/live/config/0050-locales                 locales=de_DE
    # /lib/live/config/0160-keyboard-configuration  keyboard-layouts=de
    # /lib/live/config/0070-tzdata                  timezone=Europe/Berlin
    TEXT HELP
        Boot to Debian x86 Live LXDE
        k:en, l:de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$GNURADIO_X64/casper/vmlinuz.efi" ] && sudo sh -c "echo '########################################
LABEL GNU Radio x64
    KERNEL $NFS/$GNURADIO_X64/casper/vmlinuz.efi
    APPEND initrd=$NFS/$GNURADIO_X64/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$GNURADIO_X64  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE  locales=de_DE  keyboard-layouts=de
    TEXT HELP
        Boot to GNU Radio x64 Live
        en, keyboard-layouts=de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$KALI_X64/live/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL Kali x64
    KERNEL $NFS/$KALI_X64/live/vmlinuz
    APPEND initrd=$NFS/$KALI_X64/live/initrd.img  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$KALI_X64  boot=live  noconfig=sudo  username=root  hostname=kali  --  locales=de_DE  keyboard-layouts=de
    TEXT HELP
        Boot to Kali x64 Live
        de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$DEFT_X64/casper/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL DEFT x64
    KERNEL $NFS/$DEFT_X64/casper/vmlinuz
    APPEND initrd=$NFS/$DEFT_X64/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$DEFT_X64  file=/cdrom/preseed/ubuntu.seed  boot=casper  memtest=4  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to DEFT x64 Live
        de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$PENTOO_X64/isolinux/pentoo" ] && sudo sh -c "echo '########################################
LABEL Pentoo x64
    KERNEL $NFS/$PENTOO_X64/isolinux/pentoo
    APPEND initrd=$NFS/$PENTOO_X64/isolinux/pentoo.igz  nfsroot=$IP_LOCAL:$DST_NFS/$PENTOO_X64 real_root=/dev/nfs  root=/dev/ram0  init=/linuxrc  aufs  looptype=squashfs  loop=/image.squashfs  cdroot  --  nox  keymap=de
    TEXT HELP
        Boot to Pentoo x64 Live
	en, keymap=de broken Gentoo
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$SYSTEMRESCTUE_X86/isolinux/rescue32" ] && sudo sh -c "echo '########################################
LABEL System Rescue x86
    # KERNEL $NFS/$SYSTEMRESCTUE_X86/isolinux/rescue64
    KERNEL $NFS/$SYSTEMRESCTUE_X86/isolinux/rescue32
    # APPEND initrd=$NFS/$SYSTEMRESCTUE_X86/isolinux/initram.igz  netboot=tftp://$IP_LOCAL$NFS/$SYSTEMRESCTUE_X86/sysrcd.dat  --  setkmap=de  dodhcp
    APPEND initrd=$NFS/$SYSTEMRESCTUE_X86/isolinux/initram.igz  netboot=nfs://$IP_LOCAL:$DST_NFS/$SYSTEMRESCTUE_X86  --  setkmap=de  dodhcp
    # siehe ...
    # http://www.sysresccd.org/Sysresccd-manual-en_Booting_the_CD-ROM
    # http://www.sysresccd.org/Sysresccd-manual-en_PXE_network_booting
    TEXT HELP
        Boot to System Rescue x86 Live
        de Gentoo
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$DESINFECT_X86/casper/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL desinfect x86
    KERNEL $NFS/$DESINFECT_X86/casper/vmlinuz
    APPEND initrd=$NFS/$DESINFECT_X86/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$DESINFECT_X86  file=/cdrom/preseed/ubuntu.seed  boot=casper  memtest=4  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to ct desinfect x86
        de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/$BANKIX_X86/casper/pae/vmlinuz" ] && sudo sh -c "echo '########################################
LABEL bankix x86
    KERNEL $NFS/$BANKIX_X86/casper/pae/vmlinuz
    APPEND initrd=$NFS/$BANKIX_X86/casper/pae/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/$BANKIX_X86  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
    TEXT HELP
        Boot to ct bankix Ubuntu x86 Live
        k:en, l:de
    ENDTEXT

' >> $DST_ROOT/pxelinux.cfg/default"

[ -f "$DST_ROOT/pxelinux.cfg/default" ] && [ -f "$DST_NFS/xubuntu/nonpae/casper/vmlinuz" ] && sudo sh -c "echo '########################################
#LABEL  Xubuntu 12.04.04 non-PAE
#    KERNEL $NFS/xubuntu/nonpae/casper/vmlinuz
#    APPEND initrd=$NFS/xubuntu/nonpae/casper/initrd.lz  netboot=nfs  nfsroot=$IP_LOCAL:$DST_NFS/xubuntu/nonpae  file=/cdrom/preseed/ubuntu.seed  boot=casper  --  debian-installer/language=de  console-setup/layoutcode?=de  locale=de_DE
#    TEXT HELP
#        Boot to Xubuntu non-PAE x86 Live
#        k:de, l:de/en
#    ENDTEXT
' >> $DST_ROOT/pxelinux.cfg/default"


######################################################################
[ -f /etc/dnsmasq.d/pxeboot ] || ( \
echo -e "\e[32msetup dnsmasq for pxe\e[0m";
sudo sh -c "echo '########################################
#/etc/dnsmasq.d/pxeboot

log-dhcp
log-queries

# DNS (enabled)
port=53
dns-loop-detect

# TFTP (enabled)
enable-tftp
tftp-root=$DST_ROOT/
tftp-lowercase

# PXE (enabled)
pxe-service=x86PC, \"PXE Boot Menu\", pxelinux
dhcp-boot=pxelinux.0

#dhcp-range=$IP_LOCAL_0, proxy

# do not give IPs that are in pool of DSL routers DHCP
dhcp-range=$IP_LOCAL_START, $IP_LOCAL_END, $IP_SUB, $IP_LOCAL_255, 1h

# do not handle MACs that will get IP by DSL routers DHCP
#dhcp-host=11:22:33:44:55:66, ignore # comment
' >> /etc/dnsmasq.d/pxeboot"
)


######################################################################
sudo chmod 755 $(find $DST_ROOT/ -type d) 2>/dev/null
sudo chmod 644 $(find $DST_ROOT/ -type f) 2>/dev/null
sudo chmod 755 $(find $DST_ROOT/ -type l) 2>/dev/null
sudo chown -R root:root /srv/ 2>/dev/null
sudo chown -R root:root $DST_ROOT 2>/dev/null
sudo chown -R root:root $DST_ROOT/ 2>/dev/null


######################################################################
grep -q eth0 /etc/dhcpcd.conf || ( \
echo -e "\e[32msetup dhcpcd.conf\e[0m";
sudo sh -c "echo '########################################
interface eth0
static ip_address=$IP_LOCAL/24
static routers=$IP_ROUTER
static domain_name_servers=$IP_ROUTER 8.8.8.8
' >> /etc/dhcpcd.conf"
)


######################################################################
echo -e "\e[32mDone.\e[0m";
echo -e "\e[32mPlease reboot\e[0m";
