#!/bin/bash
# 让 clang-22 兼容 clang-23 的编译参数
new=()
for a in "$@"; do
  case "$a" in
    -fms-anonymous-structs) new+=("-fms-extensions" "-Wno-microsoft-anon-tag" "-Wno-missing-declarations") ;;
    -fexperimental-late-parse-attributes|-fsplit-lto-unit) ;;
    *) new+=("$a") ;;
  esac
done
exec "${CC_BIN:-/usr/bin/clang-22}" "${new[@]}"
