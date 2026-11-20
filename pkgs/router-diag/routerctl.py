#!/usr/bin/env python3
"""
routerctl: Operational Diagnostics CLI and Policy Explainer for NixOS Router
Provides structured observability, `--json` serialization, and compile-time
firewall policy explanation.
"""

import argparse
import json
import os
import re
import subprocess
import sys

# ANSI Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
BOLD = "\033[1m"
NC = "\033[0m"


def run_cmd(cmd):
    """Run an external command and return (rc, stdout, stderr)."""
    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        return res.returncode, res.stdout, res.stderr
    except FileNotFoundError:
        return 127, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)


# ── Subcommand: Interfaces ──────────────────────────────────────────────────


def get_interfaces_data():
    data = {"interfaces": [], "offload_status": None}

    # Fetch brief addresses
    rc, out, _ = run_cmd(["ip", "-brief", "addr", "show"])
    if rc == 0:
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                dev = parts[0]
                state = parts[1].lower()
                addrs = parts[2:] if len(parts) > 2 else []

                operstate_file = f"/sys/class/net/{dev}/operstate"
                operstate = "unknown"
                if os.path.exists(operstate_file):
                    try:
                        with open(operstate_file) as f:
                            operstate = f.read().strip()
                    except Exception:
                        pass

                data["interfaces"].append(
                    {
                        "device": dev,
                        "state": state,
                        "operstate": operstate,
                        "addresses": addrs,
                    }
                )

    # Check for nic offload status
    offload_file = "/run/router/nic-offload-status.json"
    if os.path.exists(offload_file):
        try:
            with open(offload_file) as f:
                data["offload_status"] = json.load(f)
        except Exception as e:
            data["offload_status"] = {"error": f"Failed to parse offload file: {e}"}

    return data


def cmd_interfaces(args):
    data = get_interfaces_data()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0

    print(f"{YELLOW}--- Interface Status ---{NC}")
    for iface in data["interfaces"]:
        dev = iface["device"]
        state = iface["state"]
        oper = iface["operstate"]
        color = GREEN if oper == "up" else RED
        addrs = ", ".join(iface["addresses"]) if iface["addresses"] else "none"
        print(f"  {BOLD}{dev:<12}{NC} Operstate: {color}{oper:<7}{NC} State: {state:<6} Addresses: {addrs}")

    if data["offload_status"] and "interfaces" in data["offload_status"]:
        print(f"\n{YELLOW}--- Hardware Offload Profiles ---{NC}")
        off_prof = data["offload_status"].get("global_profile", "unknown")
        print(f"  Global Profile: {BOLD}{off_prof}{NC}")
        for dev, info in data["offload_status"]["interfaces"].items():
            driver = info.get("driver", "unknown")
            role = info.get("role", "unknown")
            qdisc = info.get("qdisc", "unknown")
            offloads = info.get("offloads", {})
            lro_eff = offloads.get("lro", {}).get("effective", "unknown")
            gro_eff = offloads.get("gro", {}).get("effective", "unknown")
            print(f"  {dev:<12} Driver: {driver:<10} Role: {role:<6} GRO: {gro_eff:<4} LRO: {lro_eff:<4} Qdisc: {qdisc}")

    return 0


# ── Subcommand: Health ──────────────────────────────────────────────────────


def get_health_data():
    services = [
        "health-mgmt-ip",
        "health-lan-ip",
        "health-wan-carrier",
        "health-wan-ip",
        "nftables",
        "systemd-networkd",
    ]

    checks = []
    all_passed = True
    for svc in services:
        rc, _, _ = run_cmd(["systemctl", "is-active", "--quiet", svc])
        passed = (rc == 0)
        if not passed:
            all_passed = False
        checks.append({
            "service": svc,
            "status": "PASS" if passed else "FAIL",
            "active": passed
        })

    return {
        "checks": checks,
        "allPassed": all_passed
    }


def cmd_health(args):
    data = get_health_data()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0 if data["allPassed"] else 1

    print(f"{YELLOW}--- Router Health Checks ---{NC}")
    for chk in data["checks"]:
        svc = chk["service"]
        status = chk["status"]
        color = GREEN if status == "PASS" else RED
        print(f"  {svc:<24}: {color}{status}{NC}")

    return 0 if data["allPassed"] else 1


# ── Subcommand: VPN ─────────────────────────────────────────────────────────


def get_vpn_data():
    vpn_data = {
        "wireguard": {"active": False, "interfaces": [], "output": ""},
        "tailscale": {"active": False, "status": "not running", "output": ""}
    }

    rc, out, _ = run_cmd(["wg", "show"])
    if rc == 0 and out.strip():
        vpn_data["wireguard"]["active"] = True
        vpn_data["wireguard"]["output"] = out.strip()
        lines = out.strip().splitlines()
        for line in lines:
            if line.startswith("interface:"):
                vpn_data["wireguard"]["interfaces"].append(line.split(":", 1)[1].strip())

    rc, out, _ = run_cmd(["tailscale", "status"])
    if rc == 0 and out.strip():
        vpn_data["tailscale"]["active"] = True
        vpn_data["tailscale"]["status"] = "running"
        vpn_data["tailscale"]["output"] = out.strip()

    return vpn_data


# ── Subcommand: Firewall ────────────────────────────────────────────────────


def get_firewall_summary():
    data = {
        "nftables_available": False,
        "tables": [],
        "active_counters": [],
    }

    rc, out, _ = run_cmd(["nft", "list", "tables"])
    if rc == 0:
        data["nftables_available"] = True
        data["tables"] = [line.strip() for line in out.splitlines() if line.strip()]

        rc_rules, out_rules, _ = run_cmd(["nft", "list", "ruleset"])
        if rc_rules == 0:
            for line in out_rules.splitlines():
                if re.search(r"counter packets [1-9]", line):
                    data["active_counters"].append(line.strip())

    return data


def cmd_firewall_summary(args):
    data = get_firewall_summary()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0

    print(f"{YELLOW}--- Firewall Summary (nftables) ---{NC}")
    if not data["nftables_available"]:
        print(f"{RED}Error: nft command not found or failed to list tables.{NC}")
        return 1

    print("Active tables:")
    if data["tables"]:
        for t in data["tables"]:
            print(f"  {t}")
    else:
        print("  (none)")

    print("\nRuleset statistics (non-zero counters):")
    if data["active_counters"]:
        for c in data["active_counters"]:
            print(f"  {c}")
    else:
        print("  No active counters found.")

    return 0


def cmd_firewall_explain(args):
    manifest_path = getattr(args, "manifest", None) or "/etc/router/policy-manifest.json"
    manifest = None
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path) as f:
                manifest = json.load(f)
        except Exception as e:
            err_data = {"error": f"Failed to load policy manifest from {manifest_path}: {e}"}
            if args.json:
                print(json.dumps(err_data, indent=2))
            else:
                print(f"{RED}{err_data['error']}{NC}")
            return 1

    if not manifest:
        msg = f"Policy manifest not found at {manifest_path} (services.router-zones may not be configured)."
        if args.json:
            print(json.dumps({"error": msg}, indent=2))
        else:
            print(f"{YELLOW}Notice: {msg}{NC}")
        return 1

    src_iface = getattr(args, "src_iface", None)
    dst_iface = getattr(args, "dst_iface", None)
    src_zone = getattr(args, "src_zone", None) or getattr(args, "src_zone_pos", None)
    dst_zone = getattr(args, "dst_zone", None) or getattr(args, "dst_zone_pos", None)
    proto = getattr(args, "proto", "tcp") or "tcp"
    dport = getattr(args, "dport", "any") or "any"

    iface_to_zone = manifest.get("interfaceToZone", {})

    if src_iface and not src_zone:
        src_zone = iface_to_zone.get(src_iface)
    if dst_iface and not dst_zone:
        dst_zone = iface_to_zone.get(dst_iface)

    zones = manifest.get("zones", {})
    policies = manifest.get("policies", [])

    matched_policy = None
    if src_zone and dst_zone:
        for pol in policies:
            if pol.get("fromZone") == src_zone and pol.get("toZone") == dst_zone:
                matched_policy = pol
                break

    decision = "DROP"
    action = "drop"
    chain = f"zone_{src_zone}_forward" if src_zone else "unknown"
    matching_rule = None
    reason = ""

    if matched_policy:
        action = matched_policy.get("action", "accept")
        decision = "ALLOW" if action == "accept" else ("REJECT" if action == "reject" else "DROP")
        matching_rule = f"{src_zone} -> {dst_zone}"
        reason = f"Explicit zone policy match: {src_zone} -> {dst_zone} (action: {action})"
    elif src_zone and src_zone in zones:
        zone_info = zones[src_zone]
        def_action = zone_info.get("defaultForwardAction", "return")
        action = def_action
        if def_action == "return":
            decision = "DROP"
            matching_rule = f"{src_zone} default (return)"
            reason = f"No explicit policy; zone '{src_zone}' default is return (blocked by base router-firewall forward chain)."
        elif def_action == "accept":
            decision = "ALLOW"
            matching_rule = f"{src_zone} default (accept)"
            reason = f"No explicit policy; fell back to zone '{src_zone}' defaultForwardAction: accept."
        else:
            decision = "DROP" if def_action == "drop" else "REJECT"
            matching_rule = f"{src_zone} default ({def_action})"
            reason = f"No explicit policy; fell back to zone '{src_zone}' defaultForwardAction: {def_action}."
    else:
        decision = "UNKNOWN"
        reason = "Could not resolve source or destination interface to a configured zone."

    result = {
        "decision": decision,
        "action": action,
        "srcIface": src_iface,
        "srcZone": src_zone,
        "dstIface": dst_iface,
        "dstZone": dst_zone,
        "proto": proto,
        "dport": dport,
        "chain": chain,
        "matchingRule": matching_rule,
        "reason": reason,
    }

    if args.json:
        print(json.dumps(result, indent=2))
        return 0

    dec_color = GREEN if decision == "ALLOW" else RED
    print(f"{YELLOW}--- Firewall Policy Resolution ---{NC}")
    print(f"  Source Interface:      {src_iface or 'unspecified'} (Zone: {src_zone or 'unknown'})")
    print(f"  Destination Interface: {dst_iface or 'unspecified'} (Zone: {dst_zone or 'unknown'})")
    print(f"  Protocol / Port:       {proto} / {dport}")
    print(f"  Decision:              {dec_color}{BOLD}{decision}{NC}")
    print(f"  Action:                {action}")
    print(f"  Nftables Chain:        {chain}")
    print(f"  Matching Rule:         {matching_rule or 'none'}")
    print(f"  Reason:                {reason}")

    return 0


def cmd_firewall_trace(args):
    src_iface = getattr(args, "src_iface", None) or "any"
    proto = getattr(args, "proto", None) or "ip"
    dport = getattr(args, "dport", None)

    msg = {
        "action": "trace",
        "instructions": (
            "To trace live packets in nftables:\n"
            f"1. Run: nft add rule inet filter forward iifname '{src_iface}' meta nftrace set 1 comment 'routerctl-trace'\n"
            "2. Stream trace events: nft monitor trace\n"
            "3. Cleanup rule: nft delete rule inet filter forward handle <handle>"
        ),
        "filter": {
            "srcIface": src_iface,
            "proto": proto,
            "dport": dport
        }
    }

    if args.json:
        print(json.dumps(msg, indent=2))
        return 0

    print(f"{YELLOW}--- Live Packet Tracing (nftrace) ---{NC}")
    print(msg["instructions"])
    return 0


# ── Subcommand: Status ──────────────────────────────────────────────────────


def cmd_status(args):
    hostname = "unknown"
    if os.path.exists("/proc/sys/kernel/hostname"):
        try:
            with open("/proc/sys/kernel/hostname") as f:
                hostname = f.read().strip()
        except Exception:
            pass

    uptime_str = "unknown"
    if os.path.exists("/proc/uptime"):
        try:
            with open("/proc/uptime") as f:
                sec = float(f.read().split()[0])
                hours = int(sec // 3600)
                mins = int((sec % 3600) // 60)
                uptime_str = f"{hours}h {mins}m ({int(sec)}s)"
        except Exception:
            pass

    ifaces_data = get_interfaces_data()
    health_data = get_health_data()
    vpn_data = get_vpn_data()
    fw_data = get_firewall_summary()

    status_obj = {
        "hostname": hostname,
        "uptime": uptime_str,
        "interfaces": ifaces_data["interfaces"],
        "offload_status": ifaces_data.get("offload_status"),
        "health": health_data,
        "vpn": vpn_data,
        "firewall": fw_data,
    }

    if args.json:
        print(json.dumps(status_obj, indent=2))
        return 0

    print(f"{BOLD}=== NixOS Router Status ({hostname}) ==={NC}")
    print(f"Uptime: {uptime_str}\n")

    cmd_interfaces(args)
    print("")
    cmd_health(args)
    print("")

    print(f"{YELLOW}--- VPN Status ---{NC}")
    wg_status = GREEN + "active" + NC if vpn_data["wireguard"]["active"] else "inactive"
    print(f"  WireGuard: {wg_status}")
    ts_status = GREEN + vpn_data["tailscale"]["status"] + NC if vpn_data["tailscale"]["active"] else "not running"
    print(f"  Tailscale: {ts_status}")
    print("")

    cmd_firewall_summary(args)

    return 0


# ── Subcommand: Diagnostics ─────────────────────────────────────────────────


def cmd_diagnostics(args):
    conntrack_count = "unknown"
    conntrack_max = "unknown"
    if os.path.exists("/proc/sys/net/netfilter/nf_conntrack_count"):
        try:
            with open("/proc/sys/net/netfilter/nf_conntrack_count") as f:
                conntrack_count = int(f.read().strip())
        except Exception:
            pass
    if os.path.exists("/proc/sys/net/netfilter/nf_conntrack_max"):
        try:
            with open("/proc/sys/net/netfilter/nf_conntrack_max") as f:
                conntrack_max = int(f.read().strip())
        except Exception:
            pass

    sysctls = {}
    for sc in ["net.ipv4.ip_forward", "net.ipv6.conf.all.forwarding", "net.ipv4.tcp_congestion_control"]:
        path = f"/proc/sys/{sc.replace('.', '/')}"
        if os.path.exists(path):
            try:
                with open(path) as f:
                    sysctls[sc] = f.read().strip()
            except Exception:
                sysctls[sc] = "error"

    data = {
        "conntrack": {
            "count": conntrack_count,
            "max": conntrack_max,
            "utilization_pct": round((conntrack_count / conntrack_max * 100), 2) if isinstance(conntrack_count, int) and isinstance(conntrack_max, int) and conntrack_max > 0 else None
        },
        "sysctl": sysctls,
    }

    if args.json:
        print(json.dumps(data, indent=2))
        return 0

    print(f"{YELLOW}--- System Diagnostics ---{NC}")
    ct_pct = f"({data['conntrack']['utilization_pct']}%)" if data["conntrack"]["utilization_pct"] is not None else ""
    print(f"  Conntrack entries: {conntrack_count} / {conntrack_max} {ct_pct}")
    print("  Key Kernel Parameters:")
    for k, v in sysctls.items():
        print(f"    {k:<35}: {v}")

    return 0


# ── CLI Parser & Backward Compatibility ────────────────────────────────────


# ── Operational state: ha, leases, dns, routes ──────────────────────────────
#
# INVARIANT: every section is {"available": bool, "reason": str|None, ...}
# so scripts can tell "service not configured" from "service broken", and
# the top level carries SCHEMA_VERSION. Bump it on any incompatible change.
# SECURITY: tokens and keepalived.conf (VRRP password) are never printed or
# read into the output.

SCHEMA_VERSION = 1

HA_ROLE_FILE = "/run/router-ha/role"
HA_PENALTY_FILE = "/run/router-ha/wan-penalty"
KEA_DHCP4_SOCKET = "/run/kea/dhcp4.sock"
KEA_DHCP4_LEASES = "/var/lib/kea/dhcp4.leases"
TECHNITIUM_TOKEN_FILE = "/var/lib/private/technitium-dns-server/nix-router-api-token"
TECHNITIUM_API = "http://127.0.0.1:5380/api"


def unavailable(reason, **extra):
    out = {"available": False, "reason": reason}
    out.update(extra)
    return out


def read_text(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def unit_active(unit):
    rc, out, _ = run_cmd(["systemctl", "is-active", unit])
    return out.strip() == "active"


def kea_command(command, arguments=None, sock_path=KEA_DHCP4_SOCKET, timeout=3.0):
    """Send one command to a Kea control socket; return (response, error)."""
    import socket

    if not os.path.exists(sock_path):
        return None, f"control socket {sock_path} not found"
    req = {"command": command}
    if arguments is not None:
        req["arguments"] = arguments
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(sock_path)
            s.sendall(json.dumps(req).encode())
            buf = b""
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
                try:
                    return json.loads(buf.decode()), None
                except ValueError:
                    continue
            return json.loads(buf.decode()), None
    except PermissionError:
        return None, f"permission denied on {sock_path} (run as root)"
    except (OSError, ValueError) as e:
        return None, f"control socket error: {e}"


def get_kea_ha_state():
    resp, err = kea_command("ha-heartbeat")
    if err:
        return unavailable(err)
    if resp.get("result") != 0:
        # result 2: unsupported command, i.e. the HA hook is not loaded.
        return unavailable(f"Kea HA not enabled ({resp.get('text', 'no text')})")
    args = resp.get("arguments") or {}
    return {
        "available": True,
        "reason": None,
        "state": args.get("state"),
        "scopes": args.get("scopes", []),
        "unsent_update_count": args.get("unsent-update-count"),
    }


def get_ha_data():
    role = read_text(HA_ROLE_FILE)
    kea_ha = get_kea_ha_state()
    if role is None:
        vrrp = unavailable(f"{HA_ROLE_FILE} not found (router-ha not enabled)")
    else:
        try:
            since = int(os.stat(HA_ROLE_FILE).st_mtime)
        except OSError:
            since = None
        penalty = read_text(HA_PENALTY_FILE)
        vrrp = {
            "available": True,
            "reason": None,
            "role": role,
            "role_since": since,
            "keepalived_active": unit_active("keepalived.service"),
            # router-ha wan.healthCheck: "1" means this node yielded and its
            # VRRP priority is pinned to 1.
            "wan_health_pinned": penalty == "1",
        }
    return {"schema_version": SCHEMA_VERSION, "vrrp": vrrp, "kea_ha": kea_ha}


def cmd_ha(args):
    data = get_ha_data()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0
    print(f"{YELLOW}--- High Availability ---{NC}")
    v = data["vrrp"]
    if v["available"]:
        color = GREEN if v["role"] == "master" else (RED if v["role"] == "fault" else BLUE)
        pinned = f" {RED}(WAN health: priority pinned){NC}" if v["wan_health_pinned"] else ""
        print(f"  VRRP role:   {color}{v['role']}{NC}{pinned}")
        print(f"  keepalived:  {'active' if v['keepalived_active'] else RED + 'inactive' + NC}")
    else:
        print(f"  VRRP:        unavailable: {v['reason']}")
    k = data["kea_ha"]
    if k["available"]:
        print(f"  Kea HA:      {BOLD}{k['state']}{NC} scopes={','.join(k['scopes']) or '-'} unsent={k['unsent_update_count']}")
    else:
        print(f"  Kea HA:      unavailable: {k['reason']}")
    return 0


def parse_memfile_leases(paths, now):
    """Current DHCPv4 leases from Kea memfile CSVs (later rows win)."""
    import csv

    by_addr = {}
    for path in paths:
        try:
            with open(path, newline="") as f:
                for row in csv.DictReader(f):
                    by_addr[row.get("address")] = row
        except OSError:
            continue
    leases = []
    for addr, row in by_addr.items():
        try:
            expire = int(row.get("expire") or 0)
            valid = int(row.get("valid_lifetime") or 0)
            state = int(row.get("state") or 0)
        except ValueError:
            continue
        # valid_lifetime 0 marks a deleted lease; state 0 is "default".
        if valid == 0 or state != 0 or expire <= now:
            continue
        leases.append(
            {
                "address": addr,
                "hwaddr": row.get("hwaddr") or None,
                "hostname": row.get("hostname") or None,
                "subnet_id": int(row["subnet_id"]) if (row.get("subnet_id") or "").isdigit() else None,
                "expires": expire,
            }
        )
    return leases


def get_leases_data():
    import time

    now = int(time.time())
    base = {"schema_version": SCHEMA_VERSION}
    if not unit_active("kea-dhcp4-server.service"):
        base.update(unavailable("kea-dhcp4-server is not running (Kea not enabled or stopped)", source=None, leases=[]))
        return base
    resp, err = kea_command("lease4-get-all")
    if resp is not None and resp.get("result") in (0, 3):
        leases = []
        for lease in (resp.get("arguments") or {}).get("leases", []):
            if lease.get("state", 0) != 0:
                continue
            expire = lease.get("cltt", 0) + lease.get("valid-lft", 0)
            leases.append(
                {
                    "address": lease.get("ip-address"),
                    "hwaddr": lease.get("hw-address") or None,
                    "hostname": lease.get("hostname") or None,
                    "subnet_id": lease.get("subnet-id"),
                    "expires": expire,
                }
            )
        source = "control-socket"
    else:
        # GOTCHA: lease4-get-all needs the lease_cmds hook, which router-kea
        # loads only with dhcp4.ha; fall back to the memfile (with the
        # LFC's previous file first, so newer rows win).
        if not os.path.exists(KEA_DHCP4_LEASES):
            base.update(unavailable(err or f"{KEA_DHCP4_LEASES} not found", source=None, leases=[]))
            return base
        leases = parse_memfile_leases([KEA_DHCP4_LEASES + ".2", KEA_DHCP4_LEASES], now)
        source = "memfile"
    leases.sort(key=lambda entry: tuple(int(p) for p in (entry["address"] or "0.0.0.0").split(".")))
    base.update({"available": True, "reason": None, "source": source, "leases": leases})
    return base


def cmd_leases(args):
    data = get_leases_data()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0
    print(f"{YELLOW}--- DHCPv4 Leases ---{NC}")
    if not data["available"]:
        print(f"  unavailable: {data['reason']}")
        return 0
    import time

    now = int(time.time())
    for lease in data["leases"]:
        left = max(0, lease["expires"] - now)
        print(f"  {lease['address']:<16} {lease['hwaddr'] or '-':<18} {lease['hostname'] or '-':<24} {left}s left")
    print(f"  {len(data['leases'])} lease(s), from {data['source']}")
    return 0


def get_dns_data():
    import urllib.parse
    import urllib.request

    base = {"schema_version": SCHEMA_VERSION}
    if not unit_active("technitium-dns-server.service"):
        base.update(unavailable("technitium-dns-server is not running (Technitium not enabled or stopped)", zones=[]))
        return base
    token = read_text(TECHNITIUM_TOKEN_FILE)
    if not token:
        base.update(unavailable(f"API token {TECHNITIUM_TOKEN_FILE} not readable (run as root)", zones=[]))
        return base
    url = f"{TECHNITIUM_API}/zones/list?" + urllib.parse.urlencode({"token": token})
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            body = json.load(r)
    except Exception as e:
        # SECURITY: urllib errors can echo the URL; never include it.
        base.update(unavailable(f"Technitium API request failed: {type(e).__name__}", zones=[]))
        return base
    # GOTCHA: Technitium returns HTTP 200 for errors; check .status.
    if body.get("status") != "ok":
        base.update(unavailable(f"Technitium API error: {body.get('errorMessage', body.get('status'))}", zones=[]))
        return base
    zones = []
    for z in (body.get("response") or {}).get("zones", []):
        if z.get("internal"):
            continue
        zones.append(
            {
                "name": z.get("name"),
                "type": z.get("type"),
                "disabled": bool(z.get("disabled")),
                "soa_serial": z.get("soaSerial"),
                "sync_failed": bool(z.get("syncFailed")),
                "notify_failed": bool(z.get("notifyFailed")),
                "expired": bool(z.get("isExpired")),
            }
        )
    zones.sort(key=lambda z: z["name"] or "")
    base.update({"available": True, "reason": None, "zones": zones})
    return base


def cmd_dns(args):
    data = get_dns_data()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0
    print(f"{YELLOW}--- DNS Zones (Technitium) ---{NC}")
    if not data["available"]:
        print(f"  unavailable: {data['reason']}")
        return 0
    for z in data["zones"]:
        flags = [f for f in ("disabled", "sync_failed", "notify_failed", "expired") if z[f]]
        color = RED if flags else GREEN
        print(f"  {z['name']:<32} {z['type']:<12} serial={z['soa_serial']} {color}{','.join(flags) or 'ok'}{NC}")
    return 0


def get_routes_data():
    data = {"schema_version": SCHEMA_VERSION}
    kernel = {"available": True, "reason": None}
    for family, flag in (("ipv4", "-4"), ("ipv6", "-6")):
        rc, out, err = run_cmd(["ip", "-j", flag, "route", "show", "table", "main"])
        if rc != 0:
            kernel = unavailable(f"ip route failed: {err.strip()}")
            break
        try:
            kernel[family] = json.loads(out or "[]")
        except ValueError as e:
            kernel = unavailable(f"ip route returned invalid JSON: {e}")
            break
    data["kernel"] = kernel

    if not unit_active("frr.service"):
        data["frr"] = unavailable("frr is not running (FRR not enabled or stopped)")
    else:
        frr = {"available": True, "reason": None}
        for family, cmd in (("ipv4", "show ip route json"), ("ipv6", "show ipv6 route json")):
            rc, out, err = run_cmd(["vtysh", "-c", cmd])
            if rc != 0:
                frr = unavailable(f"vtysh failed: {(err or out).strip()}")
                break
            try:
                frr[family] = json.loads(out or "{}")
            except ValueError as e:
                frr = unavailable(f"vtysh returned invalid JSON: {e}")
                break
        data["frr"] = frr
    return data


def cmd_routes(args):
    data = get_routes_data()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0
    print(f"{YELLOW}--- Kernel Routes (main table) ---{NC}")
    k = data["kernel"]
    if k["available"]:
        for family in ("ipv4", "ipv6"):
            for r in k[family]:
                via = f" via {r['gateway']}" if r.get("gateway") else ""
                dev = f" dev {r['dev']}" if r.get("dev") else ""
                proto = f" proto {r['protocol']}" if r.get("protocol") else ""
                print(f"  {r.get('dst', '?'):<28}{via}{dev}{proto}")
    else:
        print(f"  unavailable: {k['reason']}")
    f = data["frr"]
    print(f"{YELLOW}--- FRR RIB ---{NC}")
    if f["available"]:
        for family in ("ipv4", "ipv6"):
            for prefix, entries in f[family].items():
                protos = ",".join(sorted({e.get("protocol", "?") for e in entries}))
                print(f"  {prefix:<28} {protos}")
    else:
        print(f"  unavailable: {f['reason']}")
    return 0


def build_parser():
    common_parser = argparse.ArgumentParser(add_help=False)
    common_parser.add_argument(
        "--json",
        action="store_true",
        help="Output machine-readable JSON",
    )

    parser = argparse.ArgumentParser(
        prog="routerctl",
        parents=[common_parser],
        description="Operational Diagnostics CLI and Policy Explainer",
    )

    subparsers = parser.add_subparsers(
        dest="command",
        help="Available subcommands",
    )

    # status
    subparsers.add_parser(
        "status",
        parents=[common_parser],
        help="Comprehensive router status summary",
    )

    # health
    subparsers.add_parser(
        "health",
        parents=[common_parser],
        help="Router service and network health checks",
    )

    # interfaces
    subparsers.add_parser(
        "interfaces",
        parents=[common_parser],
        help="Interface addresses, operstate, and offload profiles",
    )

    # diagnostics
    subparsers.add_parser(
        "diagnostics",
        parents=[common_parser],
        help="Kernel sysctls and connection tracking metrics",
    )

    subparsers.add_parser(
        "ha",
        parents=[common_parser],
        help="VRRP role, WAN health pin and Kea HA state",
    )
    subparsers.add_parser(
        "leases",
        parents=[common_parser],
        help="Current Kea DHCPv4 leases",
    )
    subparsers.add_parser(
        "dns",
        parents=[common_parser],
        help="Technitium zone types and sync state",
    )
    subparsers.add_parser(
        "routes",
        parents=[common_parser],
        help="Kernel main-table routes and the FRR RIB",
    )

    # firewall
    fw_parser = subparsers.add_parser(
        "firewall",
        parents=[common_parser],
        help="Firewall statistics, policy explanation, and tracing",
    )
    fw_subparsers = fw_parser.add_subparsers(
        dest="fw_subcommand",
        help="Firewall operations",
    )

    fw_subparsers.add_parser(
        "summary",
        parents=[common_parser],
        help="Firewall tables and counter hits",
    )

    explain_parser = fw_subparsers.add_parser(
        "explain",
        parents=[common_parser],
        help="Explain zone policy resolution for a flow",
    )
    explain_parser.add_argument(
        "src_zone_pos", nargs="?", help="Positional source zone (e.g. lan)"
    )
    explain_parser.add_argument(
        "dst_zone_pos", nargs="?", help="Positional destination zone (e.g. wan)"
    )
    explain_parser.add_argument(
        "--src-iface", help="Source interface name (e.g. eth1)"
    )
    explain_parser.add_argument(
        "--dst-iface", help="Destination interface name (e.g. eth0)"
    )
    explain_parser.add_argument(
        "--src-zone", help="Source zone override (e.g. lan)"
    )
    explain_parser.add_argument(
        "--dst-zone", help="Destination zone override (e.g. wan)"
    )
    explain_parser.add_argument(
        "--proto", default="tcp", help="Protocol (tcp, udp, icmp)"
    )
    explain_parser.add_argument(
        "--dport", default="any", help="Destination port"
    )
    explain_parser.add_argument(
        "--manifest", help="Custom path to policy-manifest.json"
    )

    trace_parser = fw_subparsers.add_parser(
        "trace",
        parents=[common_parser],
        help="Live packet tracing via nftrace hooks",
    )
    trace_parser.add_argument("--src-iface", help="Source interface to trace")
    trace_parser.add_argument(
        "--proto", default="ip", help="Protocol to trace"
    )
    trace_parser.add_argument("--dport", help="Destination port to trace")

    # backward compatible "show" subcommand
    show_parser = subparsers.add_parser(
        "show",
        parents=[common_parser],
        help="Legacy router-diag show command",
    )
    show_parser.add_argument(
        "topic",
        choices=["interfaces", "firewall", "vpn", "health"],
        help="Topic to show",
    )

    return parser


def main():
    parser = build_parser()

    # Handle backward-compatible router-diag arguments (e.g. `router-diag show interfaces`)
    argv = sys.argv[1:]
    if not argv:
        parser.print_help()
        sys.exit(0)

    # Translate `show <topic>` directly if needed
    if len(argv) >= 1 and argv[0] == "show":
        if len(argv) >= 2:
            topic = argv[1]
            extra_args = argv[2:]
            if topic == "interfaces":
                argv = ["interfaces"] + extra_args
            elif topic == "firewall":
                argv = ["firewall", "summary"] + extra_args
            elif topic == "health":
                argv = ["health"] + extra_args
            elif topic == "vpn":
                argv = ["status"] + extra_args
        else:
            parser.print_help()
            sys.exit(1)

    args = parser.parse_args(argv)

    if args.command == "status":
        sys.exit(cmd_status(args))
    elif args.command == "health":
        sys.exit(cmd_health(args))
    elif args.command == "interfaces":
        sys.exit(cmd_interfaces(args))
    elif args.command == "diagnostics":
        sys.exit(cmd_diagnostics(args))
    elif args.command == "ha":
        sys.exit(cmd_ha(args))
    elif args.command == "leases":
        sys.exit(cmd_leases(args))
    elif args.command == "dns":
        sys.exit(cmd_dns(args))
    elif args.command == "routes":
        sys.exit(cmd_routes(args))
    elif args.command == "firewall":
        fw_sub = getattr(args, "fw_subcommand", None) or "summary"
        if fw_sub == "explain":
            sys.exit(cmd_firewall_explain(args))
        elif fw_sub == "trace":
            sys.exit(cmd_firewall_trace(args))
        else:
            sys.exit(cmd_firewall_summary(args))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
