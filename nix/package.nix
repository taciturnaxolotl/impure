{
  lib,
  stdenvNoCC,
  zsh,
  version ? "dirty",
}:

stdenvNoCC.mkDerivation {
  pname = "impure";
  inherit version;
  src = lib.cleanSource ../.;

  nativeBuildInputs = [ zsh ];

  dontBuild = true;

  # zsh picks up a .zwc sitting next to the .zsh it sources.
  installPhase = ''
    runHook preInstall
    dir=$out/share/zsh/plugins/impure
    install -Dm444 -t $dir *.zsh
    zsh -c 'zcompile "$1"' _ $dir/instant-prompt.zsh
    runHook postInstall
  '';

  meta = {
    description = "A pure zsh prompt fork with jj, zmx and transient prompt support";
    homepage = "https://tangled.org/dunkirk.sh/impure";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
