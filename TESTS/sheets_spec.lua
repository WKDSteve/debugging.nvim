-- TESTS/sheets_spec.lua -- the feature sheets of TESTS/sheets/*.sheet.lua (testing.sheet), each run by the RPC
-- klicker in a child editor. Busted style on purpose (`.testing.lua` sets the dialect for this file only): each sheet
-- is its own case named `sheet:<id>`, the name `testing sheets report` finds the result by.
-- @cache-inputs TESTS/sheets/
---@diagnostic disable: undefined-global

local sheet = require("testing.sheet")
local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(this))

describe("test sheets", function()
  for _, path in ipairs(sheet.files(root .. "/TESTS/sheets")) do
    local s, err = sheet.load(path)
    it(s and sheet.spec_name(s) or path, function()
      assert(s, err)
      sheet.check(s, { root = root })
    end)
  end
end)
