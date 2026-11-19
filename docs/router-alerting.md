# Router alerting (`router-alerting`)

Delivers the router's Prometheus alerts to people. It runs Alertmanager on
127.0.0.1 behind the existing Prometheus and offers four kinds of receiver:

| Receiver | Options | Notes |
| --- | --- | --- |
| **ntfy** | `ntfy.urlFile`, optional `ntfy.tokenFile` | Phone push. A small local relay turns Alertmanager webhooks into ntfy messages: priority 5 for `critical`, 4 for `warning`, 3 for `info`, 2 when resolved. Works with ntfy.sh or a self-hosted server. |
| **email** | `email.{to,from,smarthost,username,passwordFile}` | Alertmanager's native SMTP, STARTTLS by default. Good as the fallback channel. |
| **webhook** | `extraWebhooks` | Any HTTP endpoint (Gotify, Matrix bridges, home automation). |
| **anything native** | `extraReceiverConfig`, `extraCredentials` | Telegram, Discord, Pushover, Slack, ... merged into the default receiver. Secrets are read from `/run/credentials/alertmanager.service/<name>`. |

Every alert carries a `host` label (Prometheus `external_labels`, defaulting to
`networking.hostName`). Notifications are titled `<alert> on <host>` and grouped
per host, so alerts from two routers never merge.

Every secret is a `*File` option loaded as a systemd credential, so agenix,
sops-nix and clan vars all work, and nothing lands in the Nix store.

```nix
services.router-alerting = {
  enable = true;
  ntfy = {
    enable = true;
    urlFile = config.age.secrets.ntfy-url.path; # https://ntfy.sh/<topic>
  };
  watchdog.pingUrlFile = config.age.secrets.healthchecks-url.path;
  newDhcpDevices.enable = true;
};
```

## Dead-man watchdog

Alerts cannot tell you that the router itself is down. With
`watchdog.pingUrlFile` set, an always-firing `Watchdog` alert is routed to
that URL every `watchdog.interval` (5 minutes). A service such as
healthchecks.io notifies you when the pings stop: router down, uplink down,
Prometheus or Alertmanager dead. Give the check a period equal to the interval
plus a few minutes of grace.

## New DHCP devices

`newDhcpDevices.enable` announces the first lease Kea gives a MAC address. It
uses Kea's `run_script` hook, which runs asynchronously so DHCP is never
delayed:

- The first run seeds the known list from the current lease file, so you are
  not flooded with every existing device.
- Each new MAC raises one `RouterNewDhcpDevice` alert (severity `info`). It
  carries the hostname and address and expires after
  `newDhcpDevices.alertMinutes`.
- Known MACs are kept in `newDhcpDevices.seenFile`. Delete a line to hear
  about that device again.

Kea 3 runs hook scripts only from its scripts directory. The module points
`KEA_HOOK_SCRIPTS_PATH` at its own script directory.

## Several routers

Set `clusterPeers` to the other routers' Alertmanager cluster addresses
(`host:9094`). Clustered Alertmanagers deduplicate, so a pair sends each
notification once, and whichever node survives keeps sending. Without peers,
clustering is off.

## Checks

- `router-alerting-eval` covers the wiring.
- `router-alerting-runtime` runs `amtool check-config`, starts Kea with the
  hook (Kea 3 rejects scripts outside its scripts path), drives the ntfy
  relay against a fake server, and plays the hook through first-run seeding,
  a new device and a renewal.
