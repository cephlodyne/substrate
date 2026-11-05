return {
  -- Completely disable Mason network installers (all LSPs/formatters live in ~/.local/bin)
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.setup = opts.setup or {}

      if vim.fn.executable("biome") == 1 then
        opts.servers.biome = { mason = false }
      end
      if vim.fn.executable("gopls") == 1 then
        opts.servers.gopls = { mason = false }
      end
      if vim.fn.executable("terraform-ls") == 1 then
        opts.servers.terraformls = {
          mason = false,
          cmd = { "terraform-ls", "serve" },
          filetypes = { "terraform", "terraform-vars", "hcl" },
        }
        opts.setup.terraformls = function()
          return true
        end
      end
    end,
  },
}
