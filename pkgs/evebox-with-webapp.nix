{
  lib,
  buildNpmPackage,
  evebox,
}:

let
  webapp = buildNpmPackage {
    pname = "evebox-webapp";
    version = evebox.version;
    src = "${evebox.src}/webapp";
    npmDepsHash = "sha256-RCO/aoCOSCuYQulhm5HBzVJTaf6AF+y/g0Ee8sQgon0=";

    preBuild = ''
      echo 'export const GIT_REV = "${evebox.version}";' > src/gitrev.ts
    '';

    installPhase = ''
      runHook preInstall
      cp -r dist "$out"
      runHook postInstall
    '';
  };
in
evebox.overrideAttrs (_old: {
  postPatch = ''
    rm -rf resources/webapp
    cp -r "${webapp}" resources/webapp
  '';
})
