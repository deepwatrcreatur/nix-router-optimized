{
  evebox,
}:

evebox.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -r webapp resources/webapp
  '';
})
