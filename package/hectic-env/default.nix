{ stdenv, writeText, substituteAll }:

# A setup hook package that provides hectic-env.sh functions
# Packages can add this to nativeBuildInputs to get access to hecticPatchInclude
stdenv.mkDerivation {
  pname = "hectic-env";
  version = "1.0";
  
  # Create setup hook that will be automatically sourced
  setupHook = substituteAll {
    src = writeText "hectic-env-setup-hook.sh" ''
      source @hecticEnv@/hectic-env.sh
    '';
    hecticEnv = placeholder "out";
  };
  
  # Install the actual script
  installPhase = ''
    mkdir -p $out/nix-support
    cp ${../overlay/hectic-env.sh} $out/hectic-env.sh
    cp $setupHook $out/nix-support/setup-hook
  '';
  
  # Make the script available directly too
  passthru = {
    script = "${placeholder "out"}/hectic-env.sh";
  };
  
  meta = {
    description = "Hectic environment setup hook providing hecticPatchInclude function";
  };
}

