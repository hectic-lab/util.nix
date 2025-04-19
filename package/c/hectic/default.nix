{ stdenv, gcc, lib, bash, inotify-tools }:

stdenv.mkDerivation {
  pname = "hectic";
  version = "1.0";
  src = ./.;
  doCheck = true;

  nativeBuildInputs = [ gcc inotify-tools ];

  buildPhase = ''
    ls
    ${bash}/bin/sh ./make.sh build
  '';

  checkPhase = ''
    ${bash}/bin/sh ./make.sh check
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/bin
    cp target/libhectic.a $out/lib/
    cp hectic.h $out/include/
    
    # Create hectic-config script
    cat > $out/bin/hectic-config <<EOF
    #!/bin/sh
    
    usage() {
      echo "Usage: hectic-config [--cflags] [--libs]"
      echo "  --cflags  Print the compiler flags"
      echo "  --libs    Print the linker flags"
      echo "  --help    Display this help message"
      exit \$1
    }
    
    if [ \$# -eq 0 ]; then
      usage 1
    fi
    
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --cflags)
          echo "-I$out/include"
          ;;
        --libs)
          echo "-L$out/lib -lhectic"
          ;;
        --help)
          usage 0
          ;;
        *)
          usage 1
          ;;
      esac
      shift
    done
    EOF
    
    chmod +x $out/bin/hectic-config
  '';

  meta = {
    description = "hectic";
    license = lib.licenses.mit;
  };
}
