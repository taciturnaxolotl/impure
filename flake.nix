{
  description = "Impure — a pure fork with jj, zmx, and transient prompt support";

  outputs =
    { self }:
    let
      impureSrc = self;
    in
    {
      homeModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.impure;
        in
        {
          options.programs.impure = {
            enable = lib.mkEnableOption "impure zsh prompt";
            execTimeThreshold = lib.mkOption {
              type = lib.types.int;
              default = 3;
              description = "Minimum seconds before showing execution time.";
            };
          };

          config = lib.mkIf cfg.enable {
            programs.zsh.initContent = lib.mkBefore ''
              source ${impureSrc}/async.zsh
              IMPURE_CMD_MAX_EXEC_TIME=${toString cfg.execTimeThreshold}
              source ${impureSrc}/impure.zsh
            '';
          };
        };
    };
}
