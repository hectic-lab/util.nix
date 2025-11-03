{ self, inputs, system, ... }: let 
  mkSys = system: opts:
  (inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.hectic
      { hectic.hardware.lenovo-ideapad-15arh7 = opts; }
    ];
  });

  cases = {
    #enable          = { enable = true;  };
    #disabled        = { enable = false; };
    #customFoo       = { enable = true; foo = "bar"; };
  };
in inputs.nixpkgs.lib.mapAttrs
    (name: opts: (mkSys system opts).config.system.build.toplevel) cases
