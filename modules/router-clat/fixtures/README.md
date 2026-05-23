# router-clat Preservation Fixtures

These fixtures are the first backend-neutral preservation cases for
`router-clat`.

They are meant to be consumed by:

- the current Python control plane
- a future Elixir control plane
- any later adapter/harness that wants to prove it preserves the public
  contract

## Fixture Types

- `artifact-*.json`
  - public backend-neutral artifact expectations
- `status-*.json`
  - public machine-readable status expectations
- `mapping-*.json`
  - mapping-store and GC/persistence expectations
- `dns-*.json`
  - DNS synthesis class expectations

## Backend Neutrality

The fixtures deliberately avoid making Tayga-specific config syntax the public
contract.

The suite includes a fake backend status fixture so future harnesses can prove
they validate the public status shape without requiring `backend.name ==
"tayga"`.
