# battery —— 内核模块 `smbx_ctl`

给 `qcom_smbx`（SMB5 / pm8150b）充电器补一个"开关充电"的能力，配合 `../software/`
的守护进程把电量控制在 **70%~80%**。

## 为什么需要它

| 想用的接口 | 实际情况 |
|---|---|
| `charge_control_end_threshold`（TLP / upower 用） | 内核里**没有**。驱动是 `qcom_smbx`（SMB5），只暴露 9 个属性 |
| `pm8150b-charger/current_max`（输入电流限制） | 可写（`USBIN_CURRENT_LIMIT_CFG` = base+0x370），但 AICL 会自动接管，实测对充电电流无稳定影响 |
| `qcom-battery/constant_charge_current_max` | 只读 |

真正管用的是 PMIC 的 **`CHARGING_ENABLE_CMD`**（`base + 0x42`，bit0），驱动只在 probe
时写它，用户态没有入口，所以只能写个 out-of-tree 模块。

## 模块暴露的两个开关

| 参数 | 作用 | 寄存器 |
|---|---|---|
| `/sys/module/smbx_ctl/parameters/charging` | `1` 允许充电 / `0` 停止充电（读回是寄存器真实值） | `base + 0x42` bit0 |
| `/sys/module/smbx_ctl/parameters/usb_input` | `1` 用 USB 供电 / `0` 暂停 USB 输入（真的靠电池跑） | `base + 0x340` bit0 |

`base` 从 DT 的 `reg` 属性读（pm8150b 上是 `0x1000`）。

```bash
echo 0 | sudo tee /sys/module/smbx_ctl/parameters/charging   # 停充（手机仍由 USB 供电）
echo 0 | sudo tee /sys/module/smbx_ctl/parameters/usb_input  # 断掉 USB 输入，靠电池跑
```

## 编译

```bash
sudo ./module/build.sh              # 编译 + 装到 /lib/modules/$(uname -r)/extra
sudo ./module/build.sh --no-install # 只编译
```

需要 `clang-22 lld-22` 和对应内核头文件（`/lib/modules/$(uname -r)/build`）。

**踩过的坑**：内核是用 **Ubuntu clang 23.1.4**（`CONFIG_LTO_CLANG_THIN=y`）编的，Debian 仓库
只有 clang-22，而 clang-23 才有的 `-fms-anonymous-structs` clang-22 不认，直接导致
`static_assert(sizeof(struct filename) % 64 == 0)` 失败。

`module/clang-wrap.sh` 是个参数翻译层：把 `-fms-anonymous-structs` 换成 `-fms-extensions`
（补 `-Wno-microsoft-anon-tag`），再丢掉 `-fexperimental-late-parse-attributes` / `-fsplit-lto-unit`。
另外 Debian 的 `/usr/lib/llvm-22/bin` 里没有 `ar/nm/strip`，build.sh 会逐项回退到 binutils。

## 装机

模块由 `../software/install.sh` 调 `module/build.sh` 编译安装，并在
`/etc/modules-load.d/smbx_ctl.conf` 里登记开机加载。单独装：

```bash
sudo ./module/build.sh && sudo modprobe smbx_ctl
```

## 内核升级之后

模块失效（`modprobe` 报 version mismatch，或 `journalctl -u smbx-charge-limit` 出现
「模块未加载」）→ 重跑 `module/build.sh`，再 `sudo smbx restart`。

## 安全说明

- 加载后内核会标 `tainted`，属正常（out-of-tree）。
- 只动两个寄存器位，且都是驱动自己用过的位；`charging=0` 不会切断手机供电（实测电流 ≈0、电压稳定）。
- 卸载模块不会恢复硬件状态（保留你最后设置的值），需要恢复就 `echo 1 > .../charging`。
