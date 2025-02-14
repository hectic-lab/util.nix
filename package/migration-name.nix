{pkgs, ...}:
pkgs.writeShellScriptBin "migration-name" ''
  curl --silent https://raw.githubusercontent.com/dwyl/english-words/master/words.txt | shuf -n2 | tr '\n' '_' | sed 's/_$//'
''
