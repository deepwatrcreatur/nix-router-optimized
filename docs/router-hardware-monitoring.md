# Router Hardware Monitoring

The "Router Hardware" Grafana dashboard (uid `router-hardware`, at
`/d/router-hardware` on the router's Grafana) graphs temperatures and SFP
optics over time. It is provisioned whenever `router.monitoring.enable` is
set.

| Panel | Source | Needs |
|---|---|---|
| CPU and board temperatures | node_exporter hwmon (`node_hwmon_temp_celsius`) | nothing extra |
| NIC chip temperature | `router_nic_asic_temperature_celsius` (mlx5 MTMP register via mstflint) | `hardwareSensors.enable` |
| SFP module temperature | `router_sfp_temperature_celsius` (SFP digital diagnostics, `ethtool -m`) | `hardwareSensors.enable` |
| SFP optical power | `router_sfp_rx_power_dbm`, `router_sfp_tx_power_dbm` | `hardwareSensors.enable` |
| Sensor collector age | `router_hw_sensors_last_run_timestamp_seconds` | `hardwareSensors.enable` |

```nix
router.monitoring = {
  enable = true;
  hardwareSensors.enable = true;   # NIC ASIC and SFP sensors
  # hardwareSensors.interval = "1min";
};
```

`hardwareSensors` runs `router-hw-sensors` (package of the same name) from a
systemd timer. It writes `/run/router-hw-sensors/router_hardware.prom` with
an atomic rename, and node_exporter's textfile collector reads it.

## What is covered

- **NIC chip temperature:** NVIDIA/Mellanox ConnectX cards (driver
  `mlx5_core`), read once per card through PCI function 0. The MTMP
  register is in units of 0.125 °C. The kernel doesn't expose this sensor
  through hwmon on ConnectX-4 Lx. Intel X520/82599 (`ixgbe`) has no
  readable sensor, so it reports nothing here.
- **SFP readings:** any module with digital diagnostics, typically optics
  (10G-SR/LR). Passive DACs and RJ45 ports have none and are skipped.
- **CPU, chipset and board temperatures** come from whatever hwmon drivers
  the host loads (`coretemp`, `k10temp`, ACPI thermal zones, `nct6775` ...).

## Reading the graphs

The dashboard draws threshold lines:
- **NIC chip:** 85 °C (orange) and 95 °C (red). A ConnectX-4 Lx reports a
  95 °C warning and a 105 °C critical threshold in MTMP.
- **SFP module:** 70 °C and 80 °C, typical commercial-grade limits.

A chip running hot in a small chassis usually needs direct airflow over the
heatsink. On a ConnectX-4 Lx, 50–65 °C is normal with airflow.

Check a card by hand:

```bash
sudo mstreg -d 01:00.0 --reg_name MTMP --get --indexes sensor_index=0x0   # temperature x 0.125
sudo ethtool -m enp1s0f1np1 | grep -iE 'temperature|power'
sudo devlink health show
```

## Linking it from the router dashboard

`services.router-dashboard.links` takes the URL, for example:

```nix
services.router-dashboard.links = [
  { label = "Hardware"; url = "https://grafana.example.com/d/router-hardware"; icon = "🌡️"; }
];
```

## Tests

- `router-monitoring-hardware-sensors-eval` and `-default-off-eval` check the
  wiring: timer, textfile collector, and the dashboard's uid and queries.
- `vm-router-hw-sensors` checks the data path in a VM: the timer runs, the
  file is world-readable for node_exporter's dynamic user, and the
  heartbeat metric reaches Prometheus. The VM has no ConnectX card or SFP.
- The NIC and SFP readings were verified on real hardware: a ConnectX-4 Lx
  (MCX4121A-ACAT) with a 10G-SR optic, at 56 °C chip and 46 °C module
  temperature.
