{ lib, writers, gcc }:
name: argsOrScript:
  if 
    lib.isAttrs argsOrScript 
    && !lib.isDerivation argsOrScript
  then
    writers.makeBinWriter (
      argsOrScript
      // {
        compileScript = ''
          # Force gcc to treat the input file as C code
          ${gcc}/bin/gcc -fsyntax-only -xc $contentPath
          if [ $? -ne 0 ]; then
            echo "Syntax check failed"
            exit 1
          fi
          ${gcc}/bin/gcc -xc -o $out $contentPath
        '';
      }
    )
    name
  else
    writers.makeBinWriter {
      compileScript = ''
        # Force gcc to treat the input file as C code
        ${gcc}/bin/gcc -fsyntax-only -xc $contentPath
        if [ $? -ne 0 ]; then
          echo "Syntax check failed"
          exit 1
        fi
        ${gcc}/bin/gcc -xc -o $out $contentPath
      '';
    }
    name
    argsOrScript
