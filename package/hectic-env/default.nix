{ stdenv }: 
stdenv.override {
  extraNativeBuildInputs =
    (stdenv.stdenv.extraNativeBuildInputs or [])
    ++ [ ./hectic-env.sh ];
}