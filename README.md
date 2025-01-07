# AtoM on NixOS

This repository enables you to run [AtoM (Access to memory)](https://accesstomemory.org/en/) on your NixOS system.

## Future plans

Eventually, all this functionality should be part of Nixpkgs/NixOS. Though for that to happen, AtoM needs to support more recent dependencies and NixOS needs the Gearman service to be packaged. The following roadmap will reflect the progress made along the way.

- [ ] AtoM needs to support PHP >= 8.2
- [ ] AtoM needs to support Elasticsearch 7
- [ ] AtoM needs to support lessc 4
- [ ] NixOS needs to have a package and module for [Gearman](http://gearman.org/)
- [ ] NixOS needs to have a package and module for AtoM itself


## Run AtoM on NixOS

Prerequisites are that you can point your DNS records to this server and that you have a public IPv4 address so that LetsEncrypt certificates can be auto-generated. Also have a look at [upstreams hardware requirements](https://accesstomemory.org/en/docs/2.8/admin-manual/installation/requirements/#minimum-hardware-requirements).

Using the module definition from this flake to run AtoM on your system is a bit more involved, as we need to make some packages availabe that were dropped from Nixpkgs or were never available in the first place.

> [!NOTE]
> This repository only works as a Nix flake for now. Ideas for how to expose it in a non-flake way, that is not too opiniated are welcome!

```nix
# Adding all the inputs of your flake to specialArgs is a neat way to
# expose the capabilities of the nixos-atom flake.
{ config, lib, pkgs, flakeInputs, ... }: {

  # Make the modules for AtoM and gearman avaible
  imports = with flakeInputs.nixos-atom.nixosModules; [
    accesstomemory
    gearmand
  ];

  # Overwrite some packages with older versions. Make sure to check the
  # definition in flake.nix wether this is desirable for you!
  nixpkgs.overlays = [ flakeInputs.nixos-atom.overlays.default ];

  services.accesstomemory = {
    enable = true;
    domain = "atom.example.name";
    title = "AtoM deployment";
    description = "Description of my AtoM deployment";
    admin = {
      # Don't write secrets to the Nix store like this, but use a secrets management solution.
      passwordFile = pkgs.writeText "secret" "1totyjfwDL2F3kSTPZQr";
      email = "atom@example.org";
    };
  };

  # I found this to be necessary when running elasticsearch6 on aarch64-linux
  services.elasticsearch.extraConf = lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 ''
    xpack.ml.enabled: false
  '';

}
```


## Run maintenance commands on the system

The `accesstomemory` user on the system will have the required `php` executable in its path. So you can simply navigate into its HOME directory and execute maintenance commands there.

```console
cd
php symfony search:populate
```
