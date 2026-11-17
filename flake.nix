{
  description = "Impure — a pure fork with jj, zmx, and transient prompt support";

  outputs =
    { self }:
    let
      version = self.shortRev or self.dirtyShortRev or "dirty";
    in
    {
      overlays.default = final: _: {
        impure = final.callPackage ./nix/package.nix { inherit version; };
      };

      homeModules.default = import ./nix/module.nix { inherit version; };
    };
}
