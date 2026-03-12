# DNS Zone Management Module - Summary

## What We Built

A NixOS module for managing DNS zones with static hosts alongside DHCP dynamic registrations. This solves the problem of maintaining infrastructure host records in version control while still allowing dynamic DHCP clients.

## Key Features

1. **Static Host Records in Git**
   - Define hosts with fixed IPs in your Nix configuration
   - Changes are tracked in version control
   - Automatic sync to Technitium DNS Server via API

2. **Coexists with DHCP**
   - Static hosts don't conflict with dynamic DHCP registrations
   - DHCP clients can still auto-register alongside static records
   - Best of both worlds: infrastructure in code, clients dynamic

3. **CNAME Aliases**
   - Add multiple aliases per host
   - Example: `gateway` can also be `router`, `dns`, `firewall`

4. **Reverse DNS Support**
   - Automatic PTR record generation
   - Configurable for multiple networks

5. **SSH Config Generation**
   - Automatically generates SSH host entries
   - Use hostnames instead of IPs in SSH config
   - Managed by NixOS home-manager

## Location

- **Module**: `nix-router-optimized/modules/dns-zone.nix`
- **Example**: `nix-router-optimized/examples/dns-zone-example.nix`
- **In Use**: `unified-nix-configuration/hosts/nixos/gateway/default.nix`

## Usage Example

```nix
services.router.dnsZone = {
  enable = true;
  zoneName = "deepwatercreature.com";
  allowDynamicUpdates = true;
  
  staticHosts = {
    gateway = {
      ipAddress = "10.10.10.1";
      aliases = [ "router" "dns" ];
    };
    attic-cache = {
      ipAddress = "10.10.11.39";
      aliases = [ "cache" ];
    };
  };
  
  reverseZone = {
    enable = true;
    networks = [ "10.10.10.0/24" "10.10.11.0/24" ];
  };
};
```

## How It Works

1. **At Build Time**
   - Module reads `staticHosts` configuration
   - Generates zone files and JSON manifests
   - Creates systemd service for syncing

2. **At Runtime**
   - Systemd service waits for Technitium to start
   - Uses Technitium API to create/update zone
   - Adds each static host record
   - Creates CNAME aliases
   - Does NOT interfere with DHCP dynamic updates

3. **For Users**
   - SSH using hostnames: `ssh gateway` instead of `ssh 10.10.10.1`
   - DNS queries work for both static and dynamic hosts
   - Changes to static hosts tracked in git

## Benefits Over Manual Management

### Before
- IP addresses hardcoded in multiple places (SSH config, etc)
- Manual DNS record updates via web UI
- No version control of DNS records
- Easy to get out of sync

### After
- Single source of truth in Nix configuration
- Automatic DNS sync on system rebuild
- All infrastructure hosts in version control
- SSH config generated automatically
- DHCP clients still work dynamically

## Integration with Your Setup

Your `unified-nix-configuration` now:
1. Imports `dns-zone` module from `nix-router-optimized`
2. Defines 14 static hosts (gateway, PVE hosts, services)
3. Allows DHCP to add dynamic hosts
4. Syncs on every `nixos-rebuild`

Next time you add a new infrastructure host:
1. Add it to `staticHosts` in gateway configuration
2. Rebuild: `sudo nixos-rebuild switch`
3. Host is automatically in DNS and SSH config
4. Changes are in git history

## Future Enhancements

Potential additions:
- Import/export from other DNS formats
- Support for other DNS record types (MX, TXT, SRV)
- Integration with other DNS servers (not just Technitium)
- Automatic discovery of hosts from NixOS configurations
- DNS-based service discovery

## Maintenance

- **Version**: Added in router flake commit 29eaa69
- **Dependencies**: Technitium DNS Server, curl
- **State**: `/var/lib/technitium-dns-server`
- **Logs**: `journalctl -u technitium-sync-static-hosts`
