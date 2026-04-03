# 02 Router DDNS Provider Shape

Status: `ready`

Suggested branch: `design/router-ddns-provider-shape`

## Goal

Define a small, explicit option schema for public DDNS updates that works well
for homelab routers without trying to cover every provider edge case up front.

## Scope

- choose the first provider shape to support cleanly
- document required secrets and record/zone inputs
- decide what, if anything, should integrate with existing public ingress or
  domain modeling

## Validation

- resulting option shape is small enough to implement without premature
  abstraction
- docs make clear that this is public DNS only, not local/internal DNS
