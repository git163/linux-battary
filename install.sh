#!/bin/bash
# install.sh —— 装运行时软件（脚本 + systemd 单元 + 配置）并编译内核模块
#   sudo ./install.sh             编译模块 + 装全部脚本/服务 + 启动
#   sudo ./install.sh --no-build  跳过编译，直接用已编好的 .ko
#
# 已存在的 /etc/default/smbx-* 不会被覆盖（保住你的区间与日志开关设置）。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行: sudo $0" >&2; exit 1; }

BUILD=1
[[ ${1:-} == --no-build ]] && BUILD=0

# 内核模块目录：本地仓库是 ../battery/module，单独分发时是 ./module
MODULE_DIR=
for cand in "$ROOT/module" "$ROOT/../battery/module"; do
	[[ -f $cand/smbx_ctl.c ]] && { MODULE_DIR=$(cd "$cand" && pwd); break; }
done
[[ -n $MODULE_DIR ]] || { echo "找不到内核模块源码（module/smbx_ctl.c）" >&2; exit 1; }

echo "== 1/5 安装命令行工具到 /usr/local/sbin =="
for f in smbx smbx-charge-limit smbx-drain smbx-battery-log smbx-battery-report smbx-battery-log-toggle; do
	install -m 0755 "$ROOT/bin/$f" "/usr/local/sbin/$f"
	echo "  /usr/local/sbin/$f"
done

echo "== 2/5 安装 systemd 单元 =="
for f in "$ROOT"/systemd/*.service "$ROOT"/systemd/*.timer; do
	install -m 0644 "$f" "/etc/systemd/system/$(basename "$f")"
	echo "  /etc/systemd/system/$(basename "$f")"
done

echo "== 3/5 安装配置 =="
install -m 0644 "$ROOT/etc/modules-load.d/smbx_ctl.conf" /etc/modules-load.d/smbx_ctl.conf
for conf in smbx-battery-log:日志开关 smbx-charge-limit:电量区间; do
	name=${conf%%:*}; desc=${conf##*:}
	if [[ -f /etc/default/$name ]]; then
		echo "  /etc/default/$name 已存在（$desc），保留原设置"
	else
		install -m 0644 "$ROOT/etc/default/$name" "/etc/default/$name"
		echo "  /etc/default/$name（$desc，默认值）"
	fi
done

echo "== 4/5 编译并安装内核模块 =="
if (( BUILD )); then
	"$MODULE_DIR/build.sh"
else
	install -D -m 0644 "$MODULE_DIR/smbx_ctl.ko" "/lib/modules/$(uname -r)/extra/smbx_ctl.ko"
	depmod -a "$(uname -r)"
	echo "  已安装预编译的 smbx_ctl.ko"
fi

echo "== 5/5 启动服务 =="
systemctl daemon-reload
modprobe -r smbx_ctl 2>/dev/null || true
modprobe smbx_ctl
systemctl enable --now smbx-charge-limit.service
systemctl enable --now smbx-battery-log.timer
systemctl start smbx-battery-log.service || true
systemctl --no-pager --lines=0 status smbx-charge-limit.service | head -3
echo
echo "安装完成。常用命令："
echo "  smbx status           # 电量 / 策略 / 日志 / 模块"
echo "  smbx report 24        # 回看电量曲线"
echo "  smbx help             # 全部命令"
