# software —— 充电封顶 80% 的运行时软件

跑在 Redmi K20 Pro（`raphael` / Debian 13 / 内核 `7.3.0-rc5-sm8150`）上的守护脚本、
systemd 单元和配置。底层靠 `../battery/module/` 的内核模块操作 PMIC。

## 结构

```
software/
├── bin/
│   ├── smbx                    ← 统一入口（status/charge/log/report/drain/restart）
│   ├── smbx-charge-limit       ← 守护进程：区间滞回 + 连续确认
│   ├── smbx-drain              ← 一次性放电到上限
│   ├── smbx-battery-log        ← 5 分钟采样写 CSV
│   ├── smbx-battery-report     ← 回看曲线
│   └── smbx-battery-log-toggle ← 日志总开关
├── systemd/                    4 个单元（charge-limit / drain / battery-log .service+.timer）
├── etc/
│   ├── modules-load.d/smbx_ctl.conf   开机加载模块
│   ├── default/smbx-charge-limit      区间配置（CAP/RESUME/CONFIRM/SAFETY/INTERVAL）
│   └── default/smbx-battery-log       日志开关（ENABLED）
└── install.sh                  装到 /usr/local/sbin、/etc/systemd/system、/etc/default
```

## 安装

```bash
sudo ./install.sh              # 编译模块 + 装脚本/服务 + 启动
sudo ./install.sh --no-build   # 用已编好的 .ko
```

## 常用命令

```bash
smbx status                       # 电量 / 策略 / 日志 / 模块，一屏看完
smbx charge off                   # 手动停止充电（on 放开）
smbx log off                      # 关掉电量日志（on 恢复，status 看状态）
smbx report 24                    # 回看最近 24 小时电量曲线（0 = 全部）
smbx drain start                  # 放电到上限（后台，靠电池跑；stop 中止）
sudo smbx restart                 # 改完 /etc/default 后重启守护进程
```

## 策略

| 条件 | 动作 |
|---|---|
| ≥ 80%（`CAP`），连续 2 次采样 | 停止充电 |
| ≤ 70%（`RESUME`），连续 2 次采样 | 恢复充电 |
| 70 ~ 80 之间 | 死区，不动 |
| ≤ 40%（`SAFETY`） | 无条件充电 |

改区间：`sudo vi /etc/default/smbx-charge-limit` 后 `sudo smbx restart`。

## 电量日志

`/var/log/smbx-battery.csv`，每 5 分钟一条，超 3MB 滚动成 `.1`：

```
time,capacity,status,current_mA,voltage_V,ac_online,charging_enabled,usb_input
2026-11-15 12:15:41,99,Charging,0,4.332,1,0,1
```

负电流=放电、正=充电；电量计单次读数有毛刺，脚本取 7 次中位数再落盘。
`smbx log off` 关掉后 timer 停、脚本也直接退出，历史文件保留。

## 内核升级之后

模块会失效（`journalctl -u smbx-charge-limit` 里出现「模块未加载」）：

```bash
sudo ../battery/module/build.sh        # 重编（依赖 clang-22 + 内核头文件）
sudo smbx restart
```

## 已知事实（实测）

- `charging=0` 时手机**仍由 USB 供电**，电池只是歇着（电流 ≈0，电压 4.33V 稳定）。
- 只有 `usb_input=0` 才是真的靠电池跑（放电 0.27~0.87A），放电脚本用的就是它。
- 插着线却显示 `Discharging` 是正常的：USB 输入限流 250~500 mA，满载时电池补差额。
