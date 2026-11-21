# DHCP relay (`router-dhcp-relay`)

Relays DHCPv4 requests from a routed segment to a central DHCP server
(RFC 1542), for example a branch VLAN whose leases live on the main Kea
server. It uses systemd-networkd's built-in relay mode (`[DHCPServer]`
`RelayTarget=`), so there is no extra daemon.

```nix
{
  services.router-dhcp-relay = {
    enable = true;
    interfaces.office = {          # a services.router-networking.routedInterfaces name
      server = "10.10.10.5";       # the central DHCP server (IPv4)
      remoteId = "branch-router";  # optional option-82 Remote ID
      # circuitId defaults to the segment's device name, e.g. "lan1";
      # set it to null to leave it out.
    };
  };
}
```

## What it configures

- The segment's `.network` (`20-router-<name>`) gets `DHCPServer=yes` with
  `RelayTarget=`, plus `RelayAgentCircuitId=` / `RelayAgentRemoteId=`
  when set.
- With `router-firewall`: UDP 67 from clients on the relayed interface, and
  UDP 67 from each server address (its replies to the relay).
- `router-kea` and `router-dhcp` skip relayed segments when they detect
  interfaces automatically. Listing a relayed segment explicitly in either
  fails evaluation, because two DHCP sources on one link both answer.

## Option 82

The relay adds the Relay Agent Information option to every request it
forwards. By default the Circuit ID is the segment's device name, so the
server can tell segments apart even when they share a relay address range.
Remote ID is off unless you set it. Values are sent as plain strings.

On a Kea server, match them in a client class and keep them with the lease:

```nix
services.kea.dhcp4.settings = {
  store-extended-info = true;   # keeps option 82 in the lease database
  client-classes = [
    {
      name = "office";
      test = "relay4[1].hex == 'lan1' and relay4[2].hex == 'branch-router'";
    }
  ];
  # subnet4 = [ { subnet = "10.20.0.0/24"; pools = [ { pool = "..."; client-classes = [ "office" ]; } ]; } ];
};
```

## Server requirements

- A subnet matching the relayed segment. The server picks it from the relay
  address (giaddr), which is the router's address on that segment.
- A route back to that segment via the relay router, since replies go to
  the giaddr.

## Coexistence with a local server

A router can relay one segment and serve others with Kea on the same host.
networkd's relay and Kea both use UDP 67 without conflict; the VM test runs
exactly this.

## Tested

`vm-router-dhcp-relay`: a central Kea server only leases to requests whose
option 82 carries the expected Circuit ID and Remote ID. The office client
gets a lease through the relay and the lease stores both suboptions. A
second segment on the same router is served by its local Kea. Eval checks
live in `tests/router-dhcp-relay.nix`.
