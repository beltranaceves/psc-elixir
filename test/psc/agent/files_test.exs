defmodule Psc.Agent.FilesTest do
  use Psc.DataCase, async: true

  alias Psc.Agent.Files

  defp draft(path, content \\ "hello") do
    %{"path" => path, "description" => "", "content" => content}
  end

  test "normalizes, caps and de-duplicates drafts" do
    drafts =
      for n <- 1..(Files.max_files() + 6) do
        draft("docs/file-#{n}.md", String.duplicate("x", 1_000))
      end

    normalized = Files.normalize_drafts(drafts)

    assert length(normalized) == Files.max_files()
    assert Enum.all?(normalized, &(&1["byte_size"] <= Files.max_bytes()))

    assert [%{"path" => "one.md"}] =
             Files.normalize_drafts([draft("one.md"), draft("one.md")])

    assert Files.normalize_drafts([draft("", "body")]) == []
    assert Files.normalize_drafts([draft("  ", "x")]) == []
  end

  test "nested paths are kept, traversal is collapsed and hidden folders are dropped" do
    assert [%{"path" => "docs/spec/bento.md", "name" => "bento.md"}] =
             Files.normalize_drafts([draft("docs\\spec\\bento.md")])

    assert [%{"path" => "escape.md"}] = Files.normalize_drafts([draft("../escape.md")])
    assert Files.normalize_drafts([draft(".git/config")]) == []
    assert Files.normalize_drafts([draft("node_modules/pkg/index.js")]) == []
    assert Files.normalize_drafts([draft("docs/.hidden.md")]) == []
  end

  test "a name-only draft keeps working" do
    assert [%{"path" => "brief.md", "name" => "brief.md"}] =
             Files.normalize_drafts([%{"name" => "brief.md", "content" => "x"}])
  end

  test "the total byte budget is enforced" do
    content = String.duplicate("x", Files.max_bytes())
    drafts = for n <- 1..Files.max_files(), do: draft("file-#{n}.md", content)

    assert length(Files.normalize_drafts(drafts)) ==
             div(Files.max_total_bytes(), Files.max_bytes())
  end

  test "merge_uploads replaces paths and skips junk" do
    existing = [draft("README.md", "old")]

    uploads = [
      %{"path" => "docs\\brief.md", "content" => "new"},
      %{"path" => ".git/config", "content" => "secret"},
      %{"path" => "image.png", "content" => <<0xFF, 0xFE>>},
      %{"path" => "big.txt", "content" => String.duplicate("x", Files.max_bytes() + 1)},
      %{"path" => "README.md", "content" => "updated"}
    ]

    {files, stats} = Files.merge_uploads(existing, uploads)

    assert stats.added == 1
    assert stats.replaced == 1
    assert stats.ignored == 1
    assert stats.binary == 1
    assert stats.too_large == 1
    assert Enum.any?(files, &(&1["path"] == "docs/brief.md"))
    assert Enum.find(files, &(&1["path"] == "README.md"))["content"] == "updated"
  end

  test "tree nests files and keeps their draft indices" do
    files = [
      %{"path" => "docs/a.md"},
      %{"path" => "docs/spec/b.md"},
      %{"path" => "README.md"}
    ]

    assert [
             %{
               kind: :dir,
               name: "docs",
               children: [
                 %{
                   kind: :dir,
                   name: "spec",
                   children: [%{kind: :file, name: "b.md", index: 1}]
                 },
                 %{kind: :file, name: "a.md", index: 0}
               ]
             },
             %{kind: :file, name: "README.md", index: 2}
           ] = Files.tree(files)
  end

  test "tree shows a blank draft as a new file" do
    assert [%{kind: :file, name: "New file", index: 0}] = Files.tree([%{"path" => ""}])
  end

  test "apply_form_change updates content and path" do
    files = [Map.merge(Files.blank_draft(), %{"path" => "a.md", "name" => "a.md"})]

    files =
      Files.apply_form_change(
        files,
        ["file", "0", "content"],
        %{"file" => %{"0" => %{"content" => "body"}}}
      )

    assert [%{"content" => "body", "byte_size" => 4, "path" => "a.md"}] = files

    files =
      Files.apply_form_change(
        files,
        ["file", "0", "path"],
        %{"file" => %{"0" => %{"path" => "docs/b.md"}}}
      )

    assert [%{"path" => "docs/b.md", "name" => "b.md"}] = files

    # A stale or malformed index is ignored.
    assert Files.apply_form_change(files, ["file", "9", "path"], %{}) == files
    assert Files.apply_form_change(files, ["file", "nope", "path"], %{}) == files
  end

  test "replace stores a scope's files and drops the removed ones" do
    user = Psc.AccountsFixtures.user_fixture()

    {:ok, template} =
      Psc.Canvas.create_template(user.id, %{
        "name" => "Files #{System.unique_integer([:positive])}",
        "layout_map" => Psc.CanvasFixtures.template_layout_map_fixture()
      })

    assert {:ok, :ok} =
             Files.replace(:template, template.id, [draft("docs/a.md"), draft("b.md")])

    assert template.id |> Files.list_template() |> Enum.map(& &1.path) |> Enum.sort() ==
             ["b.md", "docs/a.md"]

    assert {:ok, :ok} = Files.replace(:template, template.id, [draft("docs/b.md", "updated")])
    [file] = Files.list_template(template.id)
    assert file.path == "docs/b.md"
    assert file.name == "b.md"
    assert file.content == "updated"
    assert file.byte_size == 7
  end

  test "copy_to_canvas copies every file into the canvas scope" do
    user = Psc.AccountsFixtures.user_fixture()

    {:ok, template} =
      Psc.Canvas.create_template(user.id, %{
        "name" => "Copy #{System.unique_integer([:positive])}",
        "layout_map" => Psc.CanvasFixtures.template_layout_map_fixture()
      })

    {:ok, :ok} = Files.replace(:template, template.id, [draft("docs/brief.md", "context")])

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{
        "name" => "Canvas",
        "cells" => Psc.Canvas.blank_cells()
      })

    Files.copy_to_canvas(template.id, canvas.id)

    assert [file] = Files.list_canvas(canvas.id)
    assert file.path == "docs/brief.md"
    assert file.name == "brief.md"
    assert file.content == "context"
    assert Files.get_canvas_file(canvas.id, "docs/brief.md").id == file.id
    assert Files.get_canvas_file(canvas.id, "brief.md").id == file.id
  end
end
