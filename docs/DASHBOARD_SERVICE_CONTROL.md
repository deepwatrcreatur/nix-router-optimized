# Dashboard Service Control Boundary

The router dashboard remains read-only by default.

This repo now supports a deliberately small authenticated mutation slice:

- all dashboard `POST` endpoints require the shared mutation token
- service control is an explicit allowlist
- the first supported service action is `restart` only

The dashboard does not support:

- arbitrary command execution
- start/stop for arbitrary units
- broad system configuration editing

## Supported Mutation Paths

- `POST /api/services/control`
  - requires `Authorization: Bearer <token>`
  - only restarts services listed in `services.router-dashboard.serviceControl.services`
- `POST /api/speedtest/run`
  - requires the same bearer token
- `POST /api/wol/wake`
  - requires the same bearer token

## NixOS Configuration

Use a runtime secret file for the shared token so it does not land in the Nix
store:

```nix
services.router-dashboard = {
  enable = true;
  services = [ "caddy" "grafana" ];

  mutationAuth.tokenFile = "/run/agenix/router-dashboard-mutation-token";

  serviceControl.services = [
    { name = "caddy"; }
  ];
};
```

Notes:

- `serviceControl.services` entries must also appear in the monitored dashboard
  service list.
- The dashboard service gets read-only access to `mutationAuth.tokenFile`.
- Restart permissions are generated only for the declared allowlisted units.

## Browser Workflow

- open the Services page
- enter the shared mutation token into the unlock field
- restart buttons appear only for explicitly allowlisted services
- the token is kept in browser session storage, not persisted as declarative
  config

## Support Stance

This feature is intentionally a local-operator convenience layer, not a general
remote administration framework.

If broader write access is needed later, it should be added as a new work item
with a separate authn/authz design rather than widening this boundary
implicitly.
