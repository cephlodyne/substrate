return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    if type(opts.ensure_installed) == "table" then
      vim.list_extend(opts.ensure_installed, { 
        "css", "html", "javascript", "typescript", "tsx", "json",
        "go", "gomod", "gowork", "gosum", 
        "terraform", "hcl", 
        "svelte"
      })
    end

    -- Disable Tree-sitter highlighting for Terraform/HCL to prevent UI freezes
    -- on complex Heredoc string interpolations. Falls back to standard regex highlighting.
    opts.highlight = opts.highlight or {}
    local prev_disable = opts.highlight.disable
    opts.highlight.disable = function(lang, buf)
      if lang == "terraform" or lang == "hcl" then
        return true
      end
      if type(prev_disable) == "function" then
        return prev_disable(lang, buf)
      elseif type(prev_disable) == "table" then
        for _, disabled_lang in ipairs(prev_disable) do
          if lang == disabled_lang then return true end
        end
      end
      return false
    end
  end,
}
