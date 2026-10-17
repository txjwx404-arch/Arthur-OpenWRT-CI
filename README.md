# 京东云亚瑟（RE-SS-01）云编译

基于 VIKINGYFY/OpenWRT-CI，源码 VIKINGYFY/immortalwrt main（满血 NSS，内核 6.18）。

- 编译：Actions → ARTHUR → Run workflow
- 插件：Config/PRIVATE.txt
- 首启分区：files/etc/init.d/arthur-disk（只用磁盘末尾未分配空间：swap 4G、/opt/docker 32G、/mnt/data 剩余），日志 /root/arthur-disk.log
- 默认地址 192.168.10.1，WiFi：Arthur / 12345678（首次登录请修改）
