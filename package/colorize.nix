{ pkgs, ... }:
pkgs.writeShellScriptBin "colorize" ''
  awk '
    BEGIN {
      # Define color codes
      RED = "\x1b[31m";
      BLUE = "\x1b[34m";
      GREEN = "\x1b[32m";
      YELLOW = "\x1b[33m";
      MAGENTA = "\x1b[35m";
      CYAN = "\x1b[36m";
      RESET = "\x1b[0m";
      IGNORECASE = 1;
    }
    {
      line = $0;
      gsub(/(^|[^A-Za-z])ERROR:/, RED "&" RESET, line);
      gsub(/(^|[^A-Za-z])DEBUG:/, BLUE "&" RESET, line);
      gsub(/(^|[^A-Za-z])INFO:/, GREEN "&" RESET, line);
      gsub(/(^|[^A-Za-z])LOG:/, GREEN "&" RESET, line);
      gsub(/(^|[^A-Za-z])EXCEPTION:/, MAGENTA "&" RESET, line);
      gsub(/(^|[^A-Za-z])WARNING:/, YELLOW "&" RESET, line);
      gsub(/(^|[^A-Za-z])NOTICE:/, CYAN "&" RESET, line);
      gsub(/(^|[^A-Za-z])HINT:/, CYAN "&" RESET, line);
      gsub(/(^|[^A-Za-z])FATAL:/, MAGENTA "&" RESET, line);
      gsub(/(^|[^A-Za-z])DETAIL:/, CYAN "&" RESET, line);
      gsub(/(^|[^A-Za-z])STATEMENT:/, CYAN "&" RESET, line);
      print line;
    }
  '
''
