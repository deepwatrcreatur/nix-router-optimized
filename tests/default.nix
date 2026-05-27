args@{
  lib,
  pkgs,
  ...
}:

let
  fineGrainedChecks = import ./fine-grained.nix args;
in
import ./suites.nix {
  inherit lib pkgs fineGrainedChecks;
}
