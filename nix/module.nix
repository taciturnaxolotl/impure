{ version }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.impure;
  inherit (lib) mkOption types;

  scalar = types.oneOf [
    types.bool
    types.int
    types.str
  ];
  render =
    yes: no: value:
    lib.escapeShellArg (
      if lib.isBool value then
        (if value then yes else no)
      else
        toString value
    );

  dir = "${cfg.package}/share/zsh/plugins/impure";

  variables = lib.mapAttrsToList (
    name: value: "typeset -g IMPURE_${name}=${render "1" "0" value}"
  ) cfg.variables;

  zstyles = lib.concatLists (
    lib.mapAttrsToList (
      context:
      lib.mapAttrsToList (
        style: value:
        "zstyle ${lib.escapeShellArg ":prompt:impure:${context}"} ${lib.escapeShellArg style} ${render "yes" "no" value}"
      )
    ) cfg.zstyles
  );
in
{
  options.programs.impure = {
    enable = lib.mkEnableOption "the impure zsh prompt";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { inherit version; };
      defaultText = lib.literalMD "impure, built from this flake";
      description = "The impure package to use.";
    };

    instantPrompt = mkOption {
      type = types.bool;
      default = true;
      description = "Print a minimal prompt before compinit and plugins load.";
    };

    variables = mkOption {
      type = types.attrsOf scalar;
      default = { };
      example = {
        CMD_MAX_EXEC_TIME = 5;
        GIT_PULL = false;
      };
      description = "`IMPURE_*` variables, without the prefix. Booleans become 1 or 0.";
    };

    zstyles = mkOption {
      type = types.attrsOf (types.attrsOf scalar);
      default = { };
      example = {
        "path:separator".dim = true;
        "git:branch".color = 242;
        git.show = false;
      };
      description = "Styles under `:prompt:impure:`, by context then style. Booleans become yes or no.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.initContent = lib.mkMerge [
      # Before compinit (570), so the placeholder shows as early as possible.
      (lib.mkIf cfg.instantPrompt (lib.mkOrder 500 "source ${dir}/instant-prompt.zsh"))
      # After the keymap (530) and setopts (950), before ordinary initContent.
      (lib.mkOrder 990 (
        lib.concatLines (
          variables
          ++ zstyles
          ++ [
            "source ${dir}/async.zsh"
            "source ${dir}/impure.zsh"
          ]
        )
      ))
    ];
  };
}
