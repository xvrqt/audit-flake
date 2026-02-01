{
  inputs = {
    # Used to keep the other inputs in lock-step
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = function:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
        ]
          (system: function nixpkgs.legacyPackages.${system});
    in
    {

      nixosModules = forAllSystems
        (pkgs: {
          default = { lib, config, ... }: {
            imports = [
              (import ./nixosModule.nix {
                inherit lib pkgs config;
              })
            ];
          };
        });
    };
}
