-- Plan shown by /cplan. Written by Claude (or by hand) and loaded on /reload.
-- Format (all fields optional except steps[].text / steps[].header):
--
-- ClaudeExportPlan = {
--   id = "unique-id",            -- change it for every new plan: resets checkmarks
--   title = "Plan title",
--   updated = "2026-11-21 14:30",
--   note = "One paragraph shown above the list.",
--   steps = {
--     { header = "Section" },
--     { text = "Step", questID = 123 },                 -- ticks itself when quest 123 is turned in
--     { text = "Step", questID = 123, when = "ready" }, -- ...when its objectives are complete
--     { text = "Step", mapID = 1436, x = 42.6, y = 71.8 }, -- ">" button sets a map pin
--   },
-- }

ClaudeExportPlan = nil
