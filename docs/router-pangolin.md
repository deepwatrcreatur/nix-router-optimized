# Pangolin (`router-pangolin`)

`services.router-pangolin` wraps the nixpkgs `services.pangolin` module
(Fossorial's tunnelled reverse proxy) for router hosts: it moves the internal
port off Grafana's 3001, opens the needed ports in `router-firewall`, and
prepares runtime files before the service starts.

## Files it manages

| Path | Owner, mode | Purpose |
| --- | --- | --- |
| `/etc/pangolin/` | `pangolin:fossorial`, `0750` | created by `systemd.tmpfiles` |
| `/etc/pangolin/pangolin.env` | `pangolin:fossorial`, `0600` | `SERVER_SECRET`, generated once by `preStart` and kept across restarts |
| `/var/lib/pangolin/server/db/*.json` | `pangolin:fossorial` | links to the package's database JSON |

`pangolin.env` is loaded as an optional `EnvironmentFile`. Deleting it makes
the next start generate a new `SERVER_SECRET`, which invalidates existing
Pangolin sessions.

## Why `/etc/pangolin` is created outside the service

The upstream unit runs as the `pangolin` user with `ProtectSystem=full`, so
`/etc` is read-only inside the service. `preStart` therefore cannot create
`/etc/pangolin` itself. The module creates the directory with tmpfiles and
adds it to `ReadWritePaths`.

Hosts that already had the directory from before upstream added the sandbox
kept working, which hid the problem until a freshly installed host failed
with `mkdir: cannot create directory '/etc/pangolin': Read-only file system`.

The `router-pangolin-etc-dir-eval` check asserts the tmpfiles rule, the
writable path and the service user.
