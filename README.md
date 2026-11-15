# battery —— 把 K20 Pro 的充电封顶在 80%

Redmi K20 Pro（`raphael`，Debian 13 + 内核 `7.3.0-rc5-sm8150`）长期插电当服务器时，
用这一套把电池控制在 **76%~80%**，顺带记录电量曲线。

## 为什么不能直接写 sysfs

| 想用的接口 | 实际情况 |
|---|---|
| `charge_control_end_threshold`（TLP / upower 用） | 内核里**没有**。驱动是 `qcom_smbx`（SMB5 / pm8150b），只暴露 9 个属性 |
| `pm8150b-charger/current_max`（输入电流限制） | 可写（`USBIN_CURRENT_LIMIT_CFG` = base+0x370），但 AICL 会自动接管，实测对充电电流无稳定影响 |
| `qcom-battery/constant_charge_current_max` | 只读 |

真正管用的是 PMIC 的 **`CHARGING_ENABLE_CMD`**（`base + 0x42`，bit0），驱动只在 probe
时写它，所以只能自己写个小模块去操作。

## 组成

| 文件 | 作用 |
|---|---|
| `module/smbx_ctl.c` | out-of-tree 内核模块，暴露两个 module param：`charging`、`usb_input` |
| `bin/smbx-charge-limit` | 守护进程脚本：≥80% 停充 / ≤76% 恢复 / ≤40% 无条件充电 |
| `bin/smbx-drain` | 一次性放电到 80%（暂停 USB 输入，让手机靠电池跑） |
| `bin/smbx-battery-log` | 每 5 分钟采样一次，写 CSV（7 次取中位数去毛刺） |
| `bin/smbx-battery-report` | 回看电量曲线：每小时 最低/最高/平均 + 充放电状态变化 |
| `bin/smbx-battery-log-toggle` | 电量日志总开关：`on` / `off` / `status` |
| `systemd/` | `smbx-charge-limit.service`、`smbx-drain.service`、`smbx-battery-log.service/.timer` |
| `etc/` | `modules-load.d/smbx_ctl.conf`（开机加载）、`default/smbx-battery-log`（日志开关） |

## 安装

```bash
sudo ./install.sh          # 编译模块 + 装全部脚本/服务 + 启动
sudo ./install.sh --no-build   # 用仓库里已有的 .ko
```

## 常用操作

```bash
# 手动开关充电（0 停 / 1 允许，读回是寄存器真实值）
echo 0 | sudo tee /sys/module/smbx_ctl/parameters/charging

# 一次性放电到 80%（数小时，靠电池跑；stop 会立刻恢复 USB 供电）
sudo systemctl start smbx-drain
sudo systemctl stop smbx-drain

# 电量历史
smbx-battery-report          # 最近 24h
smbx-battery-report 72       # 最近 72h
smbx-battery-report 0        # 全部

# 关掉 / 打开电量日志（数据保留，只是不再写）
sudo smbx-battery-log-toggle off
sudo smbx-battery-log-toggle on
smbx-battery-log-toggle status

# 阈值动作明细
journalctl -u smbx-charge-limit -n 50 --no-pager
```

## 编译踩的坑

内核是用 **Ubuntu clang 23.1.4**（`CONFIG_LTO_CLANG_THIN=y`）编的，Debian 仓库只有 clang-22，
而 clang-23 才有的 `-fms-anonymous-structs` 参数 clang-22 不认，直接导致
`static_assert(sizeof(struct filename) % 64 == 0)` 失败。

`module/clang-wrap.sh` 就是个参数翻译层：把 `-fms-anonymous-structs` 换成 `-fms-extensions`
（并补 `-Wno-microsoft-anon-tag`），再丢掉 `-fexperimental-late-parse-attributes` / `-fsplit-lto-unit`。

## 内核升级之后

模块会失效（`insmod` 报 version mismatch，或 daemon 起不来）：

```bash
sudo ./module/build.sh     # 在仓库里重编
# 或者设备上 /opt/smbx-ctl/build.sh
systemctl restart smbx-charge-limit
```

## 已知事实（实测）

- `charging=0` 时手机**仍由 USB 供电**，电池只是歇着（电流 ≈0，电压稳定 4.33V），不会自己掉电。
- `usb_input=0` 才是真的靠电池跑：`online` 变 0，放电电流 0.27~0.87A。
- 电量计单次读数毛刺很大（见过 `-793mA / 4.139V` 的假值），所以采样取中位数。
- 加载模块后内核会标 `tainted`，属正常。
