{ stdenv, patchelf, gcc, lib, bash, inotify-tools }:

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
    cp target/libhectic.so $out/lib/
    cp hectic.h $out/include/
    
    # Create hectic-config script
    cat > $out/bin/hectic-config <<EOF
    #!/bin/sh
    
    usage() {
      echo "Usage: hectic-config [--cflags] [--libs] [--static]"
      echo "  --cflags  Print the compiler flags"
      echo "  --libs    Print the linker flags (dynamic library by default)"
      echo "  --static  When used with --libs, use static linking"
      echo "  --help    Display this help message"
      exit \$1
    }
    
    if [ \$# -eq 0 ]; then
      usage 1
    fi
    
    static=0
    
    for arg in "\$@"; do
      if [ "\$arg" = "--static" ]; then
        static=1
      fi
    done
    
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --cflags)
          echo "-I$out/include"
          ;;
        --libs)
          if [ \$static -eq 1 ]; then
            echo "-L$out/lib -static -lhectic"
          else
            echo "-L$out/lib -lhectic"
          fi
          ;;
        --static)
          # Already processed above
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
