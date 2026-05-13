---
name: integration-contract-with-unified-config
description: Use this skill to keep the boundary explicit between reusable router-flake capabilities in this repo and site-specific topology or host policy owned by the consuming environment repo.
when_to_use: Use when deciding whether a change, interpretation, or follow-up belongs in nix-router-optimized or in unified-nix-configuration.
---

# Integration contract with unified config

Use this skill to classify router work at the architectural boundary between this
flake and the consuming environment repo.

## Core rule

Keep reusable router capabilities in `nix-router-optimized`. Keep concrete site
intent and topology interpretation in the consuming environment repo unless there
is a strong reason to generalize it here.

## What belongs in nix-router-optimized

This repo should own reusable, environment-agnostic router building blocks such
as:
- NixOS modules, options, assertions, and package definitions that can serve more than one site
- shared capability layers such as firewall, VPN, DHCP, DNS, HA, observability, and `router-diag`
- generic defaults and validation checks that prove module behavior without requiring one specific deployment topology
- interface-role derivation logic only when it is expressed as a reusable module contract rather than a single site's wiring

## What belongs in unified-nix-configuration

The consuming environment repo should usually own site-specific intent such as:
- concrete host imports, role assignment, and promotion policy
- physical topology interpretation, interface naming conventions, and which link is meant to be WAN/LAN on a given deployment
- secrets, addresses, hostnames, DDNS identity, and other environment source-of-truth inputs
- final composition decisions for one site, including when two reusable capabilities are enabled together for a specific router pair

## Split ownership cases

Some changes cross the boundary. In those cases:
1. put the reusable abstraction, option surface, or assertion in `nix-router-optimized`
2. put the concrete values and topology-specific interpretation in `unified-nix-configuration`
3. document the seam explicitly in commit/PR notes so future operators know where to look next

## Read-only operator implication

When a read-only tool such as `router-diag` shows runtime state, treat that output
as observation, not as definitive architecture. The consuming environment repo may
still be the source of truth for what that state is supposed to mean.

## Stop conditions

Stop when one of these is true:
- you have clearly assigned the work to `nix-router-optimized`
- you have clearly assigned the work to `unified-nix-configuration`
- you have split the work into a reusable flake concern plus a consumer-specific concern

If the next step depends on site intent, physical topology, or consumer-side
source-of-truth that is not encoded in this repo, stop and hand off to the
consuming environment repo instead of guessing.
