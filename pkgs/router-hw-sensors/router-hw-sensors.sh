# router-hw-sensors: write NIC and SFP sensor readings as node_exporter
# textfile metrics. CPU and board temperatures already come from the
# node_exporter hwmon collector; this adds what hwmon doesn't expose.
#
# Usage: router-hw-sensors <textfile-directory>

out_dir=${1:?usage: router-hw-sensors <textfile-directory>}
out="$out_dir/router_hardware.prom"

asic=()
sfp_temp=()
sfp_rx=()
sfp_tx=()

# Extract the dBm value from an ethtool -m line such as
# "Receiver signal average optical power : 0.4508 mW / -3.46 dBm".
dbm() { sed -n 's|.*/ *\(-\{0,1\}[0-9.]*\) dBm.*|\1|p' | head -n1; }

for dev in /sys/class/net/*; do
  [ -e "$dev/device/driver" ] || continue
  name=$(basename "$dev")
  drv=$(basename "$(readlink -f "$dev/device/driver")")
  pci=$(basename "$(readlink -f "$dev/device")")

  if [ "$drv" = mlx5_core ] && [[ $pci == *.0 ]]; then
    # One ASIC per card, so read it once through function 0. MTMP reports
    # units of 0.125 degrees C (NVIDIA PRM, MTMP register).
    raw=$(mstreg -d "$pci" --reg_name MTMP --get --indexes sensor_index=0x0 2>/dev/null \
      | awk '$1 == "temperature" { print $3; exit }')
    if [ -n "$raw" ]; then
      value=$(( raw ))
      # MTMP is a signed 16-bit field.
      [ "$value" -ge 32768 ] && value=$(( value - 65536 ))
      asic+=("router_nic_asic_temperature_celsius{device=\"$name\",pci=\"$pci\",driver=\"$drv\"} $(awk -v r="$value" 'BEGIN { printf "%.3f", r * 0.125 }')")
    fi
  fi

  # SFP digital diagnostics (DDM); DACs and RJ45 ports have none.
  if module=$(ethtool -m "$name" 2>/dev/null); then
    t=$(printf '%s\n' "$module" | sed -n 's|^[[:space:]]*Module temperature[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9.]*\) degrees C.*|\1|p' | head -n1)
    [ -n "$t" ] && sfp_temp+=("router_sfp_temperature_celsius{device=\"$name\"} $t")
    rx=$(printf '%s\n' "$module" | grep -i 'Receiver signal average optical power' | dbm || true)
    [ -n "$rx" ] && sfp_rx+=("router_sfp_rx_power_dbm{device=\"$name\"} $rx")
    tx=$(printf '%s\n' "$module" | grep -i 'Laser output power' | grep -vi 'alarm\|warning' | dbm || true)
    [ -n "$tx" ] && sfp_tx+=("router_sfp_tx_power_dbm{device=\"$name\"} $tx")
  fi
done

emit() {
  local metric=$1 help=$2; shift 2
  [ $# -gt 0 ] || return 0
  printf '# HELP %s %s\n# TYPE %s gauge\n' "$metric" "$help" "$metric"
  printf '%s\n' "$@"
}

tmp=$(mktemp "$out_dir/.router_hardware.XXXXXX")
{
  emit router_nic_asic_temperature_celsius "NIC ASIC temperature (mlx5 MTMP register)." "${asic[@]}"
  emit router_sfp_temperature_celsius "SFP/QSFP module temperature from digital diagnostics." "${sfp_temp[@]}"
  emit router_sfp_rx_power_dbm "SFP received optical power." "${sfp_rx[@]}"
  emit router_sfp_tx_power_dbm "SFP transmitted optical power." "${sfp_tx[@]}"
  printf '# HELP router_hw_sensors_last_run_timestamp_seconds Last collector run.\n# TYPE router_hw_sensors_last_run_timestamp_seconds gauge\nrouter_hw_sensors_last_run_timestamp_seconds %s\n' "$(date +%s)"
} > "$tmp"
chmod 0644 "$tmp"
# INVARIANT: atomic rename, so node_exporter never reads a partial file.
mv "$tmp" "$out"
