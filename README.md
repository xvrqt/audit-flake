# Audit Flake

Sets up kernel level auditing of file system access, and syscall use. By default it sets up rules to watch ssh connections, and user logins.

## Installation

Add this flake to your NixOS Configuration list of modules flake inputs, and add its NixOS Module to the outputs:

```nix
{
  inputs = {
    audit.url = "github:xvrqt/audit-flake"; # <--- Add this input
    # etc...
  };

  outputs = {defaults, ...} @ inputs: {
      nixos-configuration = nixpkgs.lib.nixosSystem {
        inherit pkgs;
        specialArgs = { inherit inputs; };
        modules = [
          audit.nixosModules.${system}.default  # <-- Add this module
          ./my-nix-configuration.nix
          # etc...
        ];
      };
  };
}
```

## Options

There are two options, which can you set using the following NixOS module.

```nix
{
  security = {
    auditing =  {
      # Whether or not to enable this module
      # TRUE by default.
      enable = true;
      # Whether or not to require a reboot of the system to update the rules
      # Added as a convenience so you can disable it while testing and
      # rebuilding. Don't forget to enable it again when you're finished!
      # TRUE by default;
      requireReboot = true;
    };
  };
}
```
