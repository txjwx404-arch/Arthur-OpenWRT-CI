#!/bin/bash
# 亚瑟私有扩展：iStore 应用商店 + 首启分区脚本（由 Packages.sh 在源码目录内调用）

# iStore（linkease）
git clone --depth=1 --single-branch --branch main https://github.com/linkease/istore.git ./package/istore || echo "istore clone failed"

# daede（kenzok8）：dae + daed + luci-app-daede，替换 feeds 里自带的 dae/daed
rm -rf ./feeds/packages/net/dae ./feeds/packages/net/daed ./feeds/luci/applications/luci-app-daed ./feeds/luci/applications/luci-app-dae
rm -rf ./package/feeds/packages/dae ./package/feeds/packages/daed ./package/feeds/luci/luci-app-daed ./package/feeds/luci/luci-app-dae
git clone --depth=1 --single-branch --branch main https://github.com/kenzok8/openwrt-daede.git ./package/daede || echo "daede clone failed"

# 生成固件内置文件
mkdir -p ./files/etc/init.d ./files/etc/sysctl.d ./files/etc/uci-defaults

cat > ./files/etc/init.d/arthur-disk <<'ARTHUR_EOF'
#!/bin/sh /etc/rc.common
# 亚瑟 eMMC 首启分区：只在磁盘末尾“未分配空间”新建分区，绝不改动已有分区
# 第一次启动：建分区后重启；第二次启动：格式化新分区并写入挂载配置，然后自我禁用
START=99
DISK=/dev/mmcblk0
LOG=/root/arthur-disk.log
SWAP_G=4
DOCKER_G=32

log() { echo "$(date '+%F %T') $*" >> $LOG; logger -t arthur-disk "$*"; }
dev_of() { blkid -t PARTLABEL="$1" -o device 2>/dev/null | head -n1; }

start() {
	[ -b "$DISK" ] || { log "no $DISK"; return 0; }
	command -v sgdisk >/dev/null || { log "sgdisk missing"; return 0; }

	if [ -z "$(dev_of a_data)" ]; then
		# 第一阶段：建分区
		sgdisk -e "$DISK" >> $LOG 2>&1
		FIRST=$(sgdisk -F "$DISK" 2>/dev/null | tail -n1)
		LAST=$(sgdisk -E "$DISK" 2>/dev/null | tail -n1)
		[ -n "$FIRST" ] && [ -n "$LAST" ] || { log "cannot read free space"; return 0; }
		FREE_G=$(( (LAST - FIRST) / 2097152 ))
		NEED_G=$(( SWAP_G + DOCKER_G + 8 ))
		if [ "$FREE_G" -lt "$NEED_G" ]; then
			log "free ${FREE_G}G < ${NEED_G}G, skip (nothing changed)"
			/etc/init.d/arthur-disk disable
			return 0
		fi
		log "free ${FREE_G}G, creating swap ${SWAP_G}G, docker ${DOCKER_G}G, data rest"
		sgdisk -n 0:0:+${SWAP_G}G -t 0:8200 -c 0:a_swap \
		       -n 0:0:+${DOCKER_G}G -t 0:8300 -c 0:a_docker \
		       -n 0:0:0 -t 0:8300 -c 0:a_data "$DISK" >> $LOG 2>&1 || { log "sgdisk failed"; return 0; }
		sync
		log "partitions created, rebooting"
		reboot
		return 0
	fi

	# 第二阶段：格式化 + 挂载
	SWAP=$(dev_of a_swap); DOCKER=$(dev_of a_docker); DATA=$(dev_of a_data)
	[ -z "$(blkid -o value -s TYPE $SWAP)" ] && mkswap -L a_swap "$SWAP" >> $LOG 2>&1
	[ -z "$(blkid -o value -s TYPE $DOCKER)" ] && mkfs.ext4 -F -L a_docker "$DOCKER" >> $LOG 2>&1
	[ -z "$(blkid -o value -s TYPE $DATA)" ] && mkfs.ext4 -F -L a_data "$DATA" >> $LOG 2>&1
	mkdir -p /opt/docker /mnt/data

	uci -q delete fstab.a_swap; uci -q delete fstab.a_docker; uci -q delete fstab.a_data
	uci set fstab.a_swap=swap
	uci set fstab.a_swap.device="$SWAP"
	uci set fstab.a_swap.enabled='1'
	uci set fstab.a_swap.priority='-2'
	uci set fstab.a_docker=mount
	uci set fstab.a_docker.uuid="$(blkid -o value -s UUID $DOCKER)"
	uci set fstab.a_docker.target='/opt/docker'
	uci set fstab.a_docker.fstype='ext4'
	uci set fstab.a_docker.options='rw,noatime'
	uci set fstab.a_docker.enabled='1'
	uci set fstab.a_data=mount
	uci set fstab.a_data.uuid="$(blkid -o value -s UUID $DATA)"
	uci set fstab.a_data.target='/mnt/data'
	uci set fstab.a_data.fstype='ext4'
	uci set fstab.a_data.options='rw,noatime'
	uci set fstab.a_data.enabled='1'
	uci commit fstab

	# Docker 数据目录
	if uci -q get dockerd.globals >/dev/null; then
		uci set dockerd.globals.data_root='/opt/docker/'
		uci commit dockerd
	fi

	/etc/init.d/fstab enable
	block mount >> $LOG 2>&1
	swapon "$SWAP" 2>/dev/null
	/etc/init.d/dockerd restart 2>/dev/null
	log "done: swap=$SWAP docker=$DOCKER data=$DATA"
	/etc/init.d/arthur-disk disable
}
ARTHUR_EOF

cat > ./files/etc/sysctl.d/99-arthur-swap.conf <<'ARTHUR_EOF'
vm.swappiness=10
ARTHUR_EOF

cat > ./files/etc/uci-defaults/99-arthur-disk-enable <<'ARTHUR_EOF'
#!/bin/sh
/etc/init.d/arthur-disk enable
exit 0
ARTHUR_EOF

chmod +x ./files/etc/init.d/arthur-disk ./files/etc/uci-defaults/99-arthur-disk-enable
echo "arthur private files ready"
