defmodule Psc.AdminTest do
  use Psc.DataCase

  import Ecto.Query

  import Psc.AccountsFixtures
  import Psc.NotesFixtures

  alias Psc.Admin
  alias Psc.Canvas
  alias Psc.Canvas.UnstrCanvas
  alias Psc.Repo

  describe "stats/0" do
    test "counts both event tables and unconfirmed accounts" do
      _confirmed = user_fixture()
      _unconfirmed = unconfirmed_user_fixture()

      stats = Admin.stats()

      assert stats.users == 2
      assert stats.unconfirmed_users == 1
      assert stats.canvas_events == 0
      assert stats.note_events == 0
    end
  end

  describe "trends/1" do
    test "returns one bucket per day, oldest first" do
      trends = Admin.trends()

      assert %{users: users, templates: templates, canvases: canvases, notes: notes} = trends
      assert length(users) == 14
      assert length(templates) == 14
      assert length(canvases) == 14
      assert length(notes) == 14
    end

    test "counts today's rows in the last bucket" do
      _canvas = canvas_fixture()

      trends = Admin.trends()

      assert List.last(trends.canvases) == 1
      assert Enum.sum(trends.canvases) == 1
    end

    test "accepts a window" do
      assert length(Admin.trends(3).users) == 3
    end
  end

  describe "recent/1" do
    test "returns a bounded list with authors preloaded" do
      user = user_fixture()

      canvases =
        Enum.map(1..6, fn index ->
          canvas_fixture(%{:user => user, "name" => "Canvas #{index}"})
        end)

      %{canvases: recent} = Admin.recent(5)
      ids = Enum.map(canvases, & &1.id)

      assert length(recent) == 5
      assert Enum.all?(recent, &(&1.author.id == user.id))
      assert Enum.all?(recent, &(&1.id in ids))
    end

    test "returns templates once they exist" do
      Canvas.seed_builtin_templates()

      %{templates: templates} = Admin.recent()

      assert length(templates) == 4

      assert Enum.all?(
               templates,
               &(&1.name in [
                   "Problem–Solution Canvas",
                   "Scratchpad",
                   "Bento Board",
                   "Image Board"
                 ])
             )
    end
  end

  describe "row_budget/0" do
    test "defaults to the free-tier ceiling" do
      assert Admin.row_budget() == 10_000
    end

    test "is configurable" do
      Application.put_env(:psc, :row_budget, 5_000)
      on_exit(fn -> Application.delete_env(:psc, :row_budget) end)

      assert Admin.row_budget() == 5_000
    end
  end

  describe "version/0" do
    test "returns the application version" do
      assert is_binary(Admin.version())
    end
  end

  describe "recent ordering" do
    test "puts the most recently updated row first" do
      user = user_fixture()
      older = canvas_fixture(%{:user => user, "name" => "Older"})
      newer = canvas_fixture(%{:user => user, "name" => "Newer"})

      Repo.update_all(from(c in UnstrCanvas, where: c.id == ^older.id),
        set: [updated_at: ~N[2026-01-01 00:00:00]]
      )

      Repo.update_all(from(c in UnstrCanvas, where: c.id == ^newer.id),
        set: [updated_at: ~N[2026-01-02 00:00:00]]
      )

      assert [%{name: "Newer"}, %{name: "Older"}] = Admin.recent().canvases
    end
  end
end
