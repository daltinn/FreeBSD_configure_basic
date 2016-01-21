#!/bin/sh
mirror=0
d1=
d2=
d3=
tank=rpool
tank_root=$tank/sys
dsk_label=rdsk
iface=
ip=
gw=
dns3=8.8.8.8
hostname=
tz="Europe/Kiev"
swap=2G

if [ "$mirror" == "" ]; then 
  echo "enter mirror  mode (default: 0)"
  echo "0 - for single disk"
  echo "1 - for mirror (RAID1)"
  echo "2 - for raidz (RAID5 3 HDD)"
  read mirror
fi
if [ "$mirror" == "" ]; then
  mirror=0
  echo "mirror mode: $mirror"
fi

camcontrol devlist | more
if [ "$d1" == "" ]; then 
  echo "enter name disk 1 (eg ada0, da0)"
read d1
fi
if [ "$d2" == "" ] && [ "$mirror" -ge "1" ] ; then 
  echo "enter name disk 2 (eg ada0, da0)"
read d2
fi
if [ "$d3" == "" ] && [ "$mirror" -ge "2" ] ; then 
  echo "enter name disk 3 (eg ada0, da0)"
read d3
fi

if [ "$dsk_label" == "" ]; then 
  echo "enter partition label (enter for rdsk)"
read dsk_label
fi
if [ "$dsk_label" == "" ]; then
  dsk_label=rdsk
  echo "disk label: $dsk_label"
fi

if [ "$swap" == "" ]; then 
  echo "enter swap (eg. 8G), enter for swap 16G"
read swap
fi
if [ "$swap" == "" ]; then 
  swap=16G
  echo "swap=$swap"
fi

echo "enter pool name (enter for zroot)"
read tank
if [ "$tank" == "" ]; then
  tank=zroot
  echo "pool name: $tank"
fi
tank_root=$tank/sys
echo "pool name: $tank" 		#debug

if [ "$hostname" == "" ]; then 
	echo "enter hostname (fqdn)"
read hostname
fi

#------------------------------
#echo "do you want use lagg? (y/n)"
#read lagg_use
#if [ "$lagg_use" == "y" | "$lagg_use" == "yes" | "$lagg_use" == "Y" ]; then
#	lagg_use=y
#	echo "How many lagg port used?"
#	read lagg_port_count
#	for i in $(seq 1 $lagg_port_count)
#	do
#		echo "enter port $lagg_port_count name (eg. igb0)"
#		read $lagg_port_$(seq 1 $lagg_port_count)
#	done 
#fi

#ifconfig
#if [ "$iface" == "" | "$lagg" ne "y"  ]; then
#  echo "enter interface name (eg em0, igb1, lagg0):"
#  read iface
#fi

#if [ "$ip" == "" ]; then
#  echo "enter dhcp(d) or ip address/mask (eg 10.0.0.2/24):"
#  read iface
#fi

#if [ "$ip" == "" | "$ip" == "dhcp" | "$ip" == "DHCP" | "$ip" == "d" ]; then
#  ip=DHCP
#else
#  if [ "$gw" == "" ]; then
#    echo "enter gateway address (eg 10.0.0.1):"
#    read gw

#    echo "enter DNS server 1 (enter for 8.8.8.8)"
#    read dns1
#    echo "enter DNS server 2 (enter for 4.4.4.4)"
#    read dns2
#    if [ "$dns1" == "" ]; then
#      dns1=8.8.8.8
#      echo "DNS1: $dns1"
#    fi
#    if [ "$dns2" == "" ]; then
#      dns2=4.4.4.4
#      echo "DNS2: $dns2"
#    fi
#  fi
#fi


#add ip|dhcp
#add lagg
#if name
#resolv.conf

#---------------------------

for disk in $d1 $d2 $d3 ;
do (
	echo "dsk_label="$dsk_label"_"$disk" disk=$disk d1=$d1"
	echo $dsk_label
#check dsk
	gpart show $disk
	echo "destroy all partition y/n [y]"
	read CONFIRM
	if [ "$CONFIRM" == "n" ]; then
		exit
	fi
	if [ "$CONFIRM" == "y" ]; then
		gpart destroy -F $disk
		gpart create -s gpt $disk
		gpart add -b 40 -s 984 -t freebsd-boot $disk
		gpart add -b 1024 -t freebsd-zfs -l "${dsk_label}"_"${disk}" $disk
		gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $disk
		gnop create -S 4096 /dev/gpt/"${dsk_label}"_"${disk}"
	)
done

gpart show -l

#Need rewrite with mount unionfs
mdconfig -a -t swap -s 16M
newfs /dev/md2
mount /dev/md2 /boot/zfs
sysctl kern.geom.debugflags=0x10

#zpool destroy $tank

#create zpool (need rewrite without gnop)

if [ "$mirror" == "2" ];  then 
		zpool create -m none -f $tank raidz /dev/gpt/"${dsk_label}"_"${d1}".nop /dev/gpt/"${dsk_label}"_"${d2}".nop /dev/gpt/"${dsk_label}"_"${d3}".nop
	elif [ "$mirror" == "1" ];  then 
		zpool create -m none -f $tank mirror /dev/gpt/"${dsk_label}"_"${d1}".nop /dev/gpt/"${dsk_label}"_"${d2}".nop
	elif [ "$mirror" == "0" ];  then
		zpool create -m none -f $tank /dev/gpt/"${dsk_label}"_"${d1}".nop
	else
		echo "error mirror option"
fi
#zfs set mountpoint=none $tank

zpool export $tank
for disk in $d1 $d2 $d3 ;
	do (
		gnop destroy /dev/gpt/"${dsk_label}"_"${disk}".nop
		)
	done
zpool import $tank 

zpool status #debug

zfs set atime=off $tank

zfs create -V $swap -o org.freebsd:swap=on -o checksum=off -o sync=disabled -o primarycache=none volblocksize=4k $tank/swap  #-o secondarycache=none

#			mountpiont					compression	exec		setuid		quota		reservation	
zfs create 																									$tank_root

zfs create																									$tank_root/base
zfs create -o mountpoint=none																	$tank_root/pkg
zfs create -o mountpoint=none																	$tank_root/dist
zfs create -o mountpoint=none																	$tank_root/dist/usr
zfs create 																									$tank/data

zfs create 																-o quota=8G											$tank_root/base/ROOT
zfs create -o mountpoint=/var/mnt	-o copies=2					-o quota=4G	-o reservation=1G	-o recordsize=128k			$tank_root/base/ROOT/default				#root folder
zfs create -o mountpoint=/var/mnt/usr                          			-o quota=8G	-o reservation=4G				$tank_root/base/usr 
zfs create -o mountpoint=/var/mnt/var                           -o quota=12G	-o reservation=2G			$tank_root/base/var #may be -o canmount=off
zfs create -o compression=lz4  -o exec=off     -o setuid=off   												$tank_root/base/var/crash
zfs create                      -o exec=off     -o setuid=off   											$tank_root/base/var/db
zfs create                      -o exec=off     -o setuid=off   											$tank_root/base/var/run
zfs create -o compression=lz4  -o exec=on      -o setuid=off   -o quota=2G	-o reservation=1G				$tank_root/base/var/tmp
zfs create -o compression=lz4  -o exec=off     -o setuid=off   -o quota=2G                         			$tank_root/base/var/spool
zfs create -o compression=lz4  -o exec=off     -o setuid=off   			                         			$tank_root/base/var/audit
zfs create                      -o exec=off     -o setuid=off												$tank_root/base/var/empty
zfs create -o compression=lz4  -o exec=off     -o setuid=off   -o quota=4G	-o reservation=1G				$tank_root/base/var/log
zfs create -o compression=lz4  -o exec=on      -o setuid=off   -o quota=8G	-o reservation=1G				$tank_root/base/tmp						#???????
zfs create -o compression=gzip  -o exec=off     -o setuid=off												$tank_root/base/var/mail							#check hierarhy

zfs create -o mountpoint=/var/mnt/usr/src -o compression=gzip -o exec=off	-o setuid=off													$tank_root/dist/usr/src #wiki.fbsd compress=lz4
zfs create -o mountpoint=/var/mnt/usr/obj -o compression=lz4 																				$tank_root/dist/usr/obj

zfs create -o mountpoint=/var/mnt/usr/local																-p	$tank_root/pkg/usr/local       #TEST!!!
zfs create -o compression=lz4 -o copies=2 -o  quota=300M -o reservation=20M 								$tank_root/pkg/usr/local/etc   #TEST!!!
zfs create -o mountpoint=/var/mnt/usr/ports -o compression=lz4            	-o setuid=off													$tank_root/pkg/usr/ports
zfs create -o compression=off  -o exec=off	-o setuid=off													$tank_root/pkg/usr/ports/distfiles
zfs create -o compression=off  -o exec=off	-o setuid=off													$tank_root/pkg/usr/ports/packages
zfs create -o mountpoint=/var/mnt/var/db/pkg -o compression=lz4  -o exec=on      -o setuid=off  		-p	$tank_root/pkg/var/db/pkg
zfs create -o mountpoint=/var/mnt/var/db/ports -o compression=lz4  -o exec=on      -o setuid=off  			$tank_root/pkg/var/db/ports
zfs create -o mountpoint=/var/mnt/var/db/portsnap -o compression=lz4  -o exec=on      -o setuid=off  		$tank_root/pkg/var/db/portsnap

zfs list
mount

#zfs create -o compression=lz4	-o copies=2 	-o quota=100M -o reservation=20M $tank_root/etc  #TEST not avaliable mount /etc on boot

zfs create                                                      											$tank/home
cd /var/mnt/ ; 
ln -s home usr/home

zfs create 																									$tank/data/db
zfs create 																									$tank/data/db/mysql
zfs create 																									$tank/data/db/mysql/data
zfs create -o recordsize=8k 																				$tank/data/db/mysql/myisam
zfs create										 															$tank/data/db/mysql/myisam-wal
zfs create 																									$tank/data/db/mysql/myisam-log
zfs create -o recordsize=16k -o primarycache=metadata														$tank/data/db/mysql/innodb
zfs create 																									$tank/data/db/mysql/innodb-log

zfs create -o recordsize=8k                                                                                                     $tank/data/db/postgresql

zfs list
echo "instaling FreeBSD"
######## install base system
cd /usr/freebsd-dist 
export DESTDIR=/var/mnt
for file in base.txz lib32.txz kernel.txz doc.txz # ports.txz src.txz; #fBSD9
do (cat $file | tar --unlink -xpJf - -C ${DESTDIR:-/}); done #fBSD9

chmod 1777 /var/mnt/var/tmp
chmod 1777 /var/mnt/tmp

echo "freebsd instaled"

# install base configs
cat << EOF > /var/mnt/etc/rc.conf
zfs_enable="YES"

sshd_enable="YES"
ntpd_enable="YES"
ntpd_sync_on_start="YES"
#ntpd_program="/usr/sbin/ntpd"   
#ntpd_flags="-p /var/run/ntpd.pid -f /var/db/ntpd.drift"
EOF
echo "rc.conf created"

cat << EOF > /var/mnt/etc/rc.conf.local
hostname="$hostname"
#defaultrouter=""
ifconfig_$iface="DHCP"

#cloned_interfaces="lagg0"
#ifconfig_igb0="up"
#ifconfig_igb1="up"
#ifconfig_lagg0="laggproto lacp laggport igb0 laggport igb1 192.168.0.2/24"
EOF
echo "rc.conf.local created"

cat << EOF > /var/mnt/boot/loader.conf
zfs_load="YES"
#vfs.root.mountfrom="zfs:$tank_root/base/ROOT/default"

#boot speedup
hw.memtest.tests=0

#zfs tune
#vm.kmem_size_max="6G"
#vm.kmem_size="5G"
vfs.zfs.write_limit_override=1073741824
#vfs.zfs.arc_min="256M"
#vfs.zfs.arc_max="4G"
#vfs.zfs.arc_meta_limit="5G"
#vfs.zfs.vdev.min_pending=2 #default=4 for non ahci
#vfs.zfs.vdev.max_pending=50 #default=35 for non ahci
#vfs.zfs.prefetch_disable=0
#vfs.zfs.txg.timeout=5
#vfs.zfs.txg.synctime_ms=2000
#vfs.zfs.zfetch.array_rd_sz="16m"
#vfs.zfs.zfetch.block_cap="512"

#other tune
aio_load="YES"
autoboot_delay="2"

#
kern.maxdsiz=2g
kern.dfldsiz=1g
kern.maxssiz=256m
kern.ipc.nmbclusters=320000
hw.em.rx_int_delay=500
hw.em.tx_int_delay=500
hw.em.rx_abs_int_delay=1000
hw.em.tx_abs_int_delay=1000
EOF
echo "loader.conf created"

cat << EOF > /var/mnt/etc/make.conf
WITHOUT_X11=YES
#multithread build ports
#.if !(make(*install) || make(package))
#MAKE_ARGS+=-j8
#.endif

#MySQL config use UTF
#.if ${.CURDIR:N*/ports/databases/mysql55-server} == ""
#WITH_CHARSET=utf8
#WITH_XCHARSET=all
#WITH_COLLATION=utf8_general_ci
#.endif
EOF
echo "make.conf created"

cat << EOF > /var/mnt/etc/sysctl.conf
#zfs
kern.maxvnodes=500000

#hw.intr_storm_threshold=3000

#net
kern.ipc.somaxconn=4096
security.bsd.see_other_uids=1
net.link.ether.inet.log_arp_wrong_iface=0
net.inet.tcp.sendspace=1048576
net.inet.tcp.recvspace=262144
net.inet.tcp.rfc1323=1
kern.maxfiles=262144
kern.maxfilesperproc=131072
kern.ipc.maxsockbuf=2097152
kern.ipc.maxsockets=262144
net.inet.tcp.msl=20000
net.inet.icmp.icmplim=5000
net.inet.ip.intr_queue_maxlen=500
net.inet.ip.portrange.reservedhigh=0
EOF
echo "sysctl.conf created"

mkdir /var/mnt/etc/periodic/hourly
cat << EOF > /var/mnt/etc/periodic/hourly/000.zfs-snapshot
#!/bin/sh

# If there is a global system configuration file, suck it in.
#
if [ -r /etc/defaults/periodic.conf ]
then
    . /etc/defaults/periodic.conf
    source_periodic_confs
fi

pools=$hourly_zfs_snapshot_pools
if [ -z "$pools" ]; then
    pools='tank'
fi

keep=$hourly_zfs_snapshot_keep
if [ -z "$keep" ]; then
    keep=6
fi

case "$hourly_zfs_snapshot_enable" in
    [Yy][Ee][Ss])
        . /usr/local/bin/zfs-snapshot
        do_snapshots "$pools" $keep 'hourly' "$hourly_zfs_snapshot_skip"
        ;;
    *)
        ;;
esac
EOF

#cat << EOF > /var/mnt/

cp /var/mnt/usr/share/zoneinfo/$tz /var/mnt/etc/localtime
cp /boot/zfs/zpool.cache /var/mnt/boot/zfs/zpool.cache

zfs set readonly=on $tank_root/base/var/empty

touch /var/mnt/etc/fstab

#cat /var/mnt/etc/rc.conf

export LD_LIBRARY_PATH=/mnt2/lib
echo -n "unmount?"

cd /tmp

cp /boot/zfs/zpool.cache /var/mnt/boot/zfs/zpool.cache
zpool set bootfs=$tank_root/base/ROOT/default $tank

sleep 3
zfs unmount -a

zfs set mountpoint=legacy  $tank_root/base/ROOT/default
zfs set mountpoint=/tmp $tank_root/base/tmp
zfs set mountpoint=/usr $tank_root/base/usr
zfs set mountpoint=/var $tank_root/base/var
zfs set mountpoint=/home $tank/home

zfs set mountpoint=/usr/src $tank_root/dist/usr/src
zfs set mountpoint=/usr/obj $tank_root/dist/usr/obj

zfs set mountpoint=/usr/ports $tank_root/pkg/usr/ports
zfs set mountpoint=/usr/local $tank_root/pkg/usr/local
zfs set mountpoint=/var/db/pkg $tank_root/pkg/var/db/pkg
zfs set mountpoint=/var/db/ports $tank_root/pkg/var/db/ports
zfs set mountpoint=/var/db/portsnap $tank_root/pkg/var/db/portsnap

#zfs set mountpoint=/etc $tank_root/etc

echo "######All done" 
