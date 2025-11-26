{ stdenv, symlinkJoin, jre, antlr4, runtimeShell, jdk }:

let
  hemar-grammar = stdenv.mkDerivation {
    pname = "hemar-grammar";
    version = "0.1.0";

    src = ./.; # directory with Hemar.g4

    nativeBuildInputs = [
      antlr4
      jdk
    ];

    buildPhase = ''
      antlr4 HemarLexer.g4 HemarParser.g4
      javac *.java
    '';

    installPhase = ''
      mkdir -p "$out/lib" "$out/bin"
      cp *.class *.tokens "$out/lib"

      cat > "$out/bin/hemar-grammar" <<EOF
#!${runtimeShell}
CLASSPATH="$out/lib:${antlr4}/share/java/*"
exec ${jre}/bin/java -cp "\$CLASSPATH" org.antlr.v4.gui.TestRig Hemar hemar "\$@"
EOF
      chmod +x "$out/bin/hemar-grammar"
    '';
  };
in
symlinkJoin {
  name = "hemar-grammar";
  paths = [ hemar-grammar ];
}
