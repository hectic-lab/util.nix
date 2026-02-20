{
  inputs,
  flake,
  self,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.hectic.program.nixvim;
in {
  imports = [
    inputs.nixvim.nixosModules.nixvim
  ];

  options.hectic.program.nixvim.enable = lib.mkEnableOption "Enable hectic nixvim config";

  config = lib.mkIf cfg.enable {
    programs.nixvim = {
      enable = true;

      extraPackages = with pkgs; [ gcc ];

      colorschemes.kanagawa = {
        enable = true;
        settings.colors.theme.all = {};
      };

      opts = {
        spell      = true;
        spelllang  = [ "en" "ru" "it" ];
        tabstop    = 2;
        shiftwidth = 2;
        softtabstop = 2;
        expandtab  = true;
      };

      extraFiles = {
        "spell/ru.utf-8.spl".source = pkgs.fetchurl {
          url    = "https://ftp.nluug.nl/vim/runtime/spell/ru.utf-8.spl";
          sha256 = "sha256-6y0714ogILMLzAp8/r2s6/t6QnWBEU9muIpXeubaxU0=";
        };
        "spell/ru.utf-8.sug".source = pkgs.fetchurl {
          url    = "https://ftp.nluug.nl/vim/runtime/spell/ru.utf-8.sug";
          sha256 = "sha256-6r2GForYXVv7gGiAjPeYK6sDdK/CmctJ7MidcWFvOTs=";
        };
        "spell/it.utf-8.spl".source = pkgs.fetchurl {
          url  = "https://ftp.nluug.nl/vim/runtime/spell/it.utf-8.spl";
          hash = "sha256-2AczkD6DbVN5DAq4wcLyn2Y8oqd67ns4Guprh2KudBM=";
        };
        "spell/it.utf-8.sug".source = pkgs.fetchurl {
          url  = "https://ftp.nluug.nl/vim/runtime/spell/it.utf-8.sug";
          hash = "sha256-4LsXYaeScJJrdaj69PTQ2EDVWis0UY/Y5RKSfCckzko=";
        };
        "ftdetect/hemar.vim".text = ''
          au BufRead,BufNewFile *.hemar setfiletype hemar
        '';
        "queries/hemar/highlights.scm".text = ''
          (interpolation)      @keyword

          (for "for"   @keyword)
          (for "in"    @keyword)
          (done "done" @keyword)

          (path)   @field
          (string) @string
          (text)   @text

          (for
            "{[" @punctuation.bracket
            "]}" @punctuation.bracket)

          (done
            "{[" @punctuation.bracket
            "]}" @punctuation.bracket)

          (interpolation
            "{[" @punctuation.bracket
            "]}" @punctuation.bracket)
        '';
      };

      extraConfigLuaPre = /* lua */ ''
        -- map leader
        vim.api.nvim_set_keymap("", "<Space>", "<Nop>", { noremap = true, silent = true })
        vim.g.mapleader = ' '

        -- render markdown
        require('render-markdown').setup({
          link = {
            enabled = true,
            render_modes = false,
          },
        })

        -- nowrap for *.nowrap.* markdown files
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "markdown",
          callback = function()
            if vim.fn.expand("%:t"):find("%.nowrap%.") then vim.opt_local.wrap = false end
          end,
        })

        -- toggle conceallevel
        vim.keymap.set("n", "<leader>tc", ":setlocal <C-R>=&conceallevel ? 'conceallevel=0' : 'conceallevel=2'<CR><CR>", { desc = "[T]oggle [C]onceallevel" })

        -- tree-sitter: register hemar parser
        local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
        parser_config.hemar = {
          install_info = {
            url   = "https://github.com/hectic-lab/util.nix",
            files = { "package/hemar/grammar/tree-sitter/src/parser.c" },
            generate_requires_npm      = false,
            requires_generate_from_grammar = false,
          },
          filetype = "hemar",
        }
      '';

      extraConfigLuaPost = /* lua */ ''
        vim.cmd [[
          hi Normal   guibg=none ctermbg=none
          hi NonText  guibg=none ctermbg=none
        ]]
      '';

      keymaps = [
        { mode = "n"; key = "<leader>o";  options.silent = true; action = "<cmd>Oil<CR>"; }
        { mode = "n"; key = "<leader>dd"; action = "<cmd>lua vim.diagnostic.open_float()<CR>"; }
        { mode = "n"; key = "<leader>dn"; action = "<cmd>lua vim.diagnostic.goto_next()<CR>"; }
        { mode = "n"; key = "<leader>dp"; action = "<cmd>lua vim.diagnostic.goto_prev()<CR>"; }
      ];

      extraPlugins = with pkgs.vimPlugins; [
        nvim-treesitter-parsers.templ
        vim-shellcheck
        vim-grammarous
      ];

      plugins = {
        render-markdown.enable = true;
        fidget.enable          = true;
        oil.enable             = true;

        treesitter = {
          enable = true;
          settings = {
            ensure_installed   = [ "hemar" ];
            highlight.enable   = true;
          };
        };

        lsp = {
          enable = true;
          keymaps.lspBuf = {
            "<leader>lh" = "hover";
            "<leader>ld" = "definition";
            "<leader>lD" = "references";
            "<leader>lr" = "rename";
            "<leader>li" = "implementation";
            "<leader>lt" = "type_definition";
            "<leader>lf" = "format";
            "<leader>la" = "code_action";
          };
          servers = {
            rust_analyzer = {
              enable        = true;
              installRustc  = false;
              installCargo  = false;
            };
            nixd = {
              enable = true;
            };
            nil_ls = {
              enable        = true;
              extraOptions.formatting.command = [ "nixpkgs-fmt" ];
            };
            clangd.enable                    = true;
            ts_ls.enable                     = true;
            gopls.enable                     = true;
            templ.enable                     = true;
            bashls.enable                    = true;
            kotlin_language_server.enable    = true;
            metals = {
              enable = true;
              cmd    = [ "metals" ];
            };
            sqls.enable                      = true;
            java_language_server.enable      = true;
            pyright.enable                   = true;
          };
        };
      };
    };
  };
}
