#!/bin/bash
# 编译并安装 smbx_ctl 内核模块（内核升级后需要重新执行）
#   sudo ./build.sh                就地编译 + 装到 /lib/modules/$(uname -r)/extra
#   sudo ./build.sh --no-install   只编译
#
# 说明：内核用 clang 23 编译（LTO thin），Debian 仓库只有 clang-22，靠 clang-wrap.sh
# 做参数翻译；LLVM 的 ar/nm/strip 等在 Debian 上不一定有 -22 后缀的软链，
# 找不到就退回 binutils 的同名工具（这几步对模块没影响）。
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
KVER="$(uname -r)"
BUILD=/lib/modules/"$KVER"/build
LLVM_BIN=/usr/lib/llvm-22/bin
INSTALL=1
[[ ${1:-} == --no-install ]] && INSTALL=0

if [[ ! -d $BUILD ]]; then
	echo "找不到 $BUILD —— 内核头文件没装（apt install linux-headers-$KVER）" >&2
	exit 1
fi

# CC / LD 必须用 clang 系（内核是 clang+LTO 编的）
CC_BIN=$(command -v clang-22 || echo "$LLVM_BIN/clang")
LD_BIN=$(command -v ld.lld-22 || echo "$LLVM_BIN/ld.lld")
for t in "$CC_BIN" "$LD_BIN"; do
	[[ -x $t ]] || { echo "缺少 $t（apt install clang-22 lld-22）" >&2; exit 1; }
done
export CC_BIN

pick() { # pick <带版本后缀的 llvm 工具> <binutils 兜底> <llvm 目录里的裸名>
	local llvm=$1 fallback=$2
	if command -v "$llvm" >/dev/null; then command -v "$llvm"
	elif [[ -x $LLVM_BIN/$3 ]]; then echo "$LLVM_BIN/$3"
	else command -v "$fallback" || echo "$fallback"; fi
}

MAKE_ARGS=(
	CC="$SRC/clang-wrap.sh"
	LD="$LD_BIN"
	AR="$(pick llvm-ar-22 ar llvm-ar)"
	NM="$(pick llvm-nm-22 nm llvm-nm)"
	STRIP="$(pick llvm-strip-22 strip llvm-strip)"
	OBJCOPY="$(pick llvm-objcopy-22 objcopy llvm-objcopy)"
	OBJDUMP="$(pick llvm-objdump-22 objdump llvm-objdump)"
)

cd "$SRC"
make -C "$BUILD" M="$SRC" "${MAKE_ARGS[@]}" modules

echo "编译完成: $SRC/smbx_ctl.ko"

(( INSTALL )) || exit 0

install -D -m 0644 "$SRC/smbx_ctl.ko" /lib/modules/"$KVER"/extra/smbx_ctl.ko
depmod -a "$KVER"
echo "已安装: $(modinfo -n smbx_ctl)"
