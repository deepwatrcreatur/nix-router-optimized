{
  lib,
  pkgs,
  fineGrainedChecks,
}:

let
  filterChecks = predicate: lib.filterAttrs predicate fineGrainedChecks;

  moduleImportChecks = filterChecks (
    name: _: lib.hasPrefix "module-" name && lib.hasSuffix "-import-eval" name
  );

  repoSurfaceChecks = filterChecks (
    name: _: builtins.elem name [
      "default-module-bundle-eval"
      "exported-module-list-eval"
    ]
  );

  docPositiveChecks = filterChecks (
    name: _:
    (lib.hasPrefix "docs-" name || lib.hasPrefix "readme-" name)
    && !(lib.hasPrefix "docs-router-clat-reject-" name)
    && !(lib.hasSuffix "-unit-tests" name)
  );

  negativeBoundaryChecks = filterChecks (
    name: _:
    lib.hasPrefix "docs-router-clat-reject-" name
    || lib.hasSuffix "-fails" name
    || lib.hasSuffix "-fails-eval" name
    || lib.hasSuffix "-assertion" name
  );

  dashboardAndUiChecks = filterChecks (
    name: _:
    lib.hasPrefix "router-dashboard-" name
    || lib.hasPrefix "router-clat-dashboard-" name
    || lib.hasSuffix "-metadata-eval" name
  );

  runtimeUnitChecks = filterChecks (
    name: _: lib.hasSuffix "-unit-tests" name
  );

  routerPositiveChecks = filterChecks (
    name: _:
    !(builtins.hasAttr name moduleImportChecks)
    && !(builtins.hasAttr name repoSurfaceChecks)
    && !(builtins.hasAttr name docPositiveChecks)
    && !(builtins.hasAttr name negativeBoundaryChecks)
    && !(builtins.hasAttr name dashboardAndUiChecks)
    && !(builtins.hasAttr name runtimeUnitChecks)
  );

  mkSuite =
    name: checks:
    let
      checkNames = builtins.attrNames checks;
      materializeChecks = lib.concatMapStringsSep "\n" (
        checkName:
        let
          drv = checks.${checkName};
        in
        ''
          cp ${drv} "$out/${checkName}"
        ''
      ) checkNames;
    in
    pkgs.runCommand name { } ''
      mkdir -p "$out"
      cat > "$out/README" <<'EOF'
      Suite: ${name}
      Included checks:
      ${lib.concatMapStringsSep "\n" (checkName: "- ${checkName}") checkNames}
      EOF
      ${materializeChecks}
    '';
in
{
  ci-module-imports = mkSuite "ci-module-imports" (repoSurfaceChecks // moduleImportChecks);
  ci-docs-and-examples = mkSuite "ci-docs-and-examples" docPositiveChecks;
  ci-router-positive-evals = mkSuite "ci-router-positive-evals" routerPositiveChecks;
  ci-router-negative-boundaries = mkSuite "ci-router-negative-boundaries" negativeBoundaryChecks;
  ci-dashboard-and-ui-contracts = mkSuite "ci-dashboard-and-ui-contracts" dashboardAndUiChecks;
  ci-runtime-unit-tests = mkSuite "ci-runtime-unit-tests" runtimeUnitChecks;
}
