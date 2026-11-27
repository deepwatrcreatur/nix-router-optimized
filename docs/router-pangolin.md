# Pangolin (`router-pangolin`)

`services.router-pangolin` wraps the nixpkgs `services.pangolin` module
(Fossorial's tunnelled reverse proxy) for router hosts: it moves the internal
port off Grafana's 3001, opens the needed ports in `router-firewall`, and
prepares runtime files before the service starts.

## Ports

| Setting (`server.*`) | Pangolin default | This module | Why |
| --- | --- | --- | --- |
| `internal_port` | 3001 | 3005 | Grafana listens on 3001 |
| `ai_gateway_port` (Pangolin 1.24+) | 3005 | 3006 | its default collides with `internal_port`; Pangolin exits with `EADDRINUSE` |

Override either through `services.router-pangolin.settings.server.<name>`
if the port is taken on your host. Releases before 1.24 ignore
`ai_gateway_port`.

## Files it manages

| Path | Owner, mode | Purpose |
| --- | --- | --- |
| `/etc/pangolin/` | `pangolin:fossorial`, `0750` | created before each start if missing; an existing directory keeps its mode |
| `/etc/pangolin/pangolin.env` | `pangolin:fossorial`, `0600` | `SERVER_SECRET`, generated once by `preStart` under `umask 077` and kept across restarts |
| `/var/lib/pangolin/server/db/*.json` | `pangolin:fossorial` | links to the package's database JSON |

`pangolin.env` is loaded as an optional `EnvironmentFile`. Deleting it makes
the next start generate a new `SERVER_SECRET`, which invalidates existing
Pangolin sessions.

## Why `/etc/pangolin` is created outside the service

The upstream unit runs as the `pangolin` user with `ProtectSystem=full`, so
`/etc` is read-only inside the service. `preStart` therefore cannot create
`/etc/pangolin` itself. The module adds a first `ExecStartPre` with the `+`
prefix, which runs as root outside the sandbox and creates the directory if
it is missing, and lists the directory in `ReadWritePaths`. Doing this on
every start rather than with tmpfiles also covers the directory being
deleted while the system runs.

Hosts that already had the directory from before upstream added the sandbox
kept working, which hid the problem until a freshly installed host failed
with `mkdir: cannot create directory '/etc/pangolin': Read-only file system`.

The `router-pangolin-etc-dir-eval` check asserts the privileged pre-start
step, the writable path and the service user.

## Gerbil version

The nixpkgs Pangolin module starts `gerbil` with `pkgs.fosrl-gerbil` named
directly. Gerbil before 1.5.2 closes its relay packet channel twice on
shutdown ([fosrl/gerbil#51](https://github.com/fosrl/gerbil/pull/51)), so
every stop ends in `panic: close of closed channel`, exit status 2, and a
failed unit. On a VRRP pair gerbil is a single-active unit that stops on
every demotion, so each handover raised a failed-unit alert.

`services.router-pangolin.gerbilPackage` defaults to nixpkgs' package when it
is 1.5.2 or newer and otherwise to a local build of 1.5.2 (1.6.0 needs Go
1.26.9). The module replaces the unit's `ExecStart` with the same arguments
and that package; `checks.router-pangolin-etc-dir-eval` asserts both. Drop
the local build once the pinned nixpkgs carries 1.5.2 or later.
