{ pkgs, ... }:
pkgs.writeShellScriptBin "pager" ''
    nvim -R --clean -c 'set buftype=nofile' -c 'nnoremap q :q!<CR>' -c 'set nowrap' \
        -c 'set runtimepath^=${pkgs.vimPlugins.vim-plugin-AnsiEsc}' \
        -c 'runtime! plugin/*.vim' -c 'AnsiEsc' -
    #                  ^^^^^^^^^^^^^^^^^^^^
    #                  Prevents Neovim from treating the buffer as a file
    #                                          ^^^^^^^^^^^^^^^^^^^^
    #                                          Makes 'q' quit Neovim immediately
    #                                                                   ^^^^^^^^^^^
    #                                                        Disables text wrapping
    #      ^^^^^^^^
    #      Enables ANSI color interpretation
''
