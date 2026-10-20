# Resets the E2E database's canvas data.
#
# Every E2E run creates canvases and templates, and nothing removes them
# afterwards. After a few runs the canvas index lists thousands of rows, the
# LiveView re-render after a creation takes seconds, and assertions that wait
# for the flash (or for anything else in that patch) start racing the server.
#
# Only the data owned by the seeded E2E accounts is removed, so a developer's
# own database is never touched. The accounts themselves are left alone —
# they are (re)created by priv/repo/e2e_seeds.exs.
#
# Run with:
#   MIX_ENV=dev PSC_DB_NAME=psc_e2e mix run priv/repo/e2e_reset.exs

alias Psc.Accounts
alias Psc.Canvas.Layout
alias Psc.Canvas.UnstrCanvas
alias Psc.Repo

import Ecto.Query

emails = ["e2e@example.com", "e2e2@example.com"]

user_ids =
  emails
  |> Enum.map(&Accounts.get_user_by_email/1)
  |> Enum.reject(&is_nil/1)
  |> Enum.map(& &1.id)

if user_ids == [] do
  IO.puts("E2E reset: no seeded accounts yet, nothing to remove")
else
  {canvases, _} = Repo.delete_all(from(c in UnstrCanvas, where: c.author_id in ^user_ids))
  {templates, _} = Repo.delete_all(from(t in Layout, where: t.author_id in ^user_ids))

  IO.puts("E2E reset: removed #{canvases} canvases and #{templates} templates")
end
