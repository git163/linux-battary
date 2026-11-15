#!/bin/bash
# install.sh —— 把 battery/ 这整套东西装到本机（Redmi K20 Pro / Debian 13）
#   sudo ./install.sh            编译模块 + 装脚本/服务 + 启动守护进程
#   sudo ./install.sh --no-build 跳过模块编译（直接用已编好的 .ko）
#
# 已存在的 /etc/default/smbx-battery-log 不会被覆盖（保住你日志开关的设置）。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行: sudo $0" >&2; exit 1; }

BUILD=1
[[ ${1:-} == --no-build ]] && BUILD=0

echo "== 1/5 安装命令行工具到 /usr/local/sbin =="
for f in smbx-charge-limit smbx-drain smbx-battery-log smbx-battery-report smbx-battery-log-toggle; do
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
if [[ -f /etc/default/smbx-battery-log ]]; then
	echo "  /etc/default/smbx-battery-log 已存在，保留原设置"
else
	install -m 0644 "$ROOT/etc/default/smbx-battery-log" /etc/default/smbx-battery-log
	echo "  /etc/default/smbx-battery-log（默认 ENABLED=1）"
fi

echo "== 4/5 编译并安装内核模块 =="
if (( BUILD )); then
	"$ROOT/module/build.sh"
else
	install -D -m 0644 "$ROOT/module/smbx_ctl.ko" "/lib/modules/$(uname -r)/extra/smbx_ctl.ko"
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
echo "安装完成。"
echo "  状态: smbx-battery-log-toggle status"
echo "  回看: smbx-battery-report"
echo "  日志: journalctl -u smbx-charge-limit -f"
