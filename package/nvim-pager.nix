{pkgs, ...}:
pkgs.writeShellScriptBin "pager" ''
  nvim -R --clean NONE \
       -c 'nnoremap q :q!<CR>' \
       -c 'set buftype=nofile nowrap' \
       -c 'set runtimepath^=${pkgs.vimPlugins.vim-plugin-AnsiEsc}' \
       -c 'runtime! plugin/*.vim' \
       -c 'set conceallevel=3' \
       -c 'AnsiEsc' $@ -
''
