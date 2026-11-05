-- Disable aggressive visual scanners for Terraform/HCL files to prevent lockups on complex Heredocs
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "terraform", "terraform-vars", "hcl" },
  callback = function()
    vim.b.miniindentscope_disable = true
    vim.cmd("NoMatchParen")
  end,
})
