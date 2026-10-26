defmodule Psc.Agent.Files do
  @moduledoc """
  Reference documents attached to a template or a canvas.

  Rows are text, scoped to one owner, copied on instantiation, and read by the
  agent through `Psc.Agent.Tools.ReadFile`. A file's `path` is its identity and
  preserves the nested tree a directory upload brings in (`docs/spec/bento.md`);
  `name` is the basename for display.

  The caps are deliberately small: the free tier is limited to roughly ten
  thousand rows per table, and the contents travel to the user's model provider.
  A directory upload is filtered before it reaches the row budget: hidden
  folders, common build folders and binary files are skipped.
  """

  import Ecto.Query

  alias Psc.Agent.AgentFile
  alias Psc.Repo

  @max_files 24
  @max_bytes 128 * 1024
  @max_total_bytes 768 * 1024
  @max_path 240
  @max_description 200
  @max_upload_entries 100

  @ignored_segments ~w(.git .svn .hg node_modules _build deps target dist build .next .cache .idea .vscode)

  def max_files, do: @max_files
  def max_bytes, do: @max_bytes
  def max_total_bytes, do: @max_total_bytes
  def max_path, do: @max_path
  def max_description, do: @max_description
  def max_upload_entries, do: @max_upload_entries

  def list_template(template_id) when is_binary(template_id), do: list(:template, template_id)
  def list_canvas(canvas_id) when is_binary(canvas_id), do: list(:canvas, canvas_id)

  def list(scope, id) when scope in [:template, :canvas] and is_binary(id) do
    from(f in AgentFile,
      where: field(f, ^scope_field(scope)) == ^id,
      order_by: [asc: f.path, asc: f.position]
    )
    |> Repo.all()
  end

  def get(scope, id) when scope in [:template, :canvas] and is_binary(id) do
    Repo.get_by(AgentFile, [{scope_field(scope), id}])
  end

  def get_canvas_file(canvas_id, path) when is_binary(canvas_id) and is_binary(path) do
    # `name` keeps pre-path rows and old tool calls working.
    Repo.one(
      from f in AgentFile,
        where: f.canvas_id == ^canvas_id and (f.path == ^path or f.name == ^path)
    )
  end

  @doc "Drafts for the editor: the fields the form round-trips."
  def drafts(scope, id) do
    scope |> list(id) |> Enum.map(&draft/1)
  end

  def draft(%AgentFile{} = file) do
    path = file.path || file.name || ""

    %{
      "id" => file.id,
      "path" => path,
      "name" => file.name || Path.basename(path),
      "description" => file.description || "",
      "content" => file.content || "",
      "byte_size" => file.byte_size || byte_size(file.content || "")
    }
  end

  @doc "An empty draft for the 'Add file' button."
  def blank_draft do
    %{
      "id" => nil,
      "path" => "",
      "name" => "",
      "description" => "",
      "content" => "",
      "byte_size" => 0
    }
  end

  @doc """
  Replaces every file of a scope with the drafts.

  Delete-and-insert on purpose: a scope has at most six small rows, and file ids
  are not referenced anywhere else. The whole set is validated and capped first,
  so a malformed draft cannot leave a half-saved list.
  """
  def replace(scope, id, drafts) when scope in [:template, :canvas] and is_binary(id) do
    files = normalize_drafts(drafts)

    Repo.transaction(fn ->
      from(f in AgentFile, where: field(f, ^scope_field(scope)) == ^id)
      |> Repo.delete_all()

      files
      |> Enum.with_index()
      |> Enum.each(fn {file, position} ->
        attrs = %{
          path: file["path"],
          name: file["name"],
          description: file["description"],
          content: file["content"],
          byte_size: file["byte_size"],
          position: position
        }

        %AgentFile{}
        |> AgentFile.changeset(Map.put(attrs, scope_field(scope), id))
        |> Repo.insert!()
      end)

      :ok
    end)
  end

  @doc "Copies every file of a template into a canvas, preserving order."
  def copy_to_canvas(template_id, canvas_id)
      when is_binary(template_id) and is_binary(canvas_id) do
    template_id
    |> list_template()
    |> Enum.each(fn file ->
      %AgentFile{canvas_id: canvas_id}
      |> AgentFile.changeset(%{
        path: file.path || file.name,
        name: file.name,
        description: file.description,
        content: file.content,
        byte_size: file.byte_size,
        position: file.position
      })
      |> Repo.insert!()
    end)
  end

  @doc "Copies every file of one template into another (a fork)."
  def copy_to_template(source_id, target_id)
      when is_binary(source_id) and is_binary(target_id) do
    source_id
    |> list_template()
    |> Enum.each(fn file ->
      %AgentFile{template_id: target_id}
      |> AgentFile.changeset(%{
        path: file.path || file.name,
        name: file.name,
        description: file.description,
        content: file.content,
        byte_size: file.byte_size,
        position: file.position
      })
      |> Repo.insert!()
    end)
  end

  def delete_all(scope, id) when scope in [:template, :canvas] and is_binary(id) do
    from(f in AgentFile, where: field(f, ^scope_field(scope)) == ^id)
    |> Repo.delete_all()
  end

  @doc """
  Applies one field of the agent form, identified by LiveView's `_target`.

  Only existing files are updated; adding and removing rows is handled by the
  click events.
  """
  def apply_form_change(files, ["file", index, field], params)
      when is_binary(index) and field in ["path", "name", "description", "content"] do
    value = get_in(params, ["file", index, field]) || ""

    case Integer.parse(index) do
      {position, ""} when position >= 0 and position < length(files) ->
        List.update_at(files, position, fn file ->
          updated =
            if field == "path" do
              path = String.trim(value)
              file |> Map.put("path", path) |> Map.put("name", Path.basename(path))
            else
              Map.put(file, field, value)
            end

          Map.put(updated, "byte_size", byte_size(Map.get(updated, "content") || ""))
        end)

      _other ->
        files
    end
  end

  def apply_form_change(files, _target, _params), do: files

  @doc """
  Normalizes drafts into at most #{@max_files} uniquely pathed, byte-capped
  files.

  `path` is normalized (forward slashes, no `.`/`..`/empty segments). Hidden
  files and common build folders are dropped. An empty path falls back to
  `name`, so drafts from before paths existed still load. Duplicate paths keep
  the first occurrence.
  """
  def normalize_drafts(drafts) when is_list(drafts) do
    drafts
    |> Enum.map(&normalize_draft/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce([], fn file, acc ->
      if Enum.any?(acc, &(&1["path"] == file["path"])), do: acc, else: acc ++ [file]
    end)
    |> Enum.take(@max_files)
    |> take_total_bytes()
  end

  def normalize_drafts(_drafts), do: []

  @doc """
  Merges uploaded files into the current drafts.

  Uploaded files whose path already exists replace the existing draft, which
  makes re-uploading a folder a refresh rather than a duplicate. Binary, hidden
  and oversized uploads are skipped and counted.
  """
  def merge_uploads(drafts, uploads) when is_list(drafts) and is_list(uploads) do
    existing =
      drafts
      |> Enum.map(&normalize_draft/1)
      |> Enum.reject(&is_nil/1)

    existing_paths = MapSet.new(existing, & &1["path"])

    {uploaded, skipped} =
      Enum.reduce(uploads, {[], %{binary: 0, invalid: 0, ignored: 0, too_large: 0}}, fn upload,
                                                                                        {acc,
                                                                                         skipped} ->
        raw_path = upload |> field_value("path") |> to_text()
        path = normalize_path(raw_path)
        content = upload |> field_value("content") |> to_text()

        cond do
          path == "" ->
            {acc, bump(skipped, :invalid)}

          ignored_path?(path) ->
            {acc, bump(skipped, :ignored)}

          not text_content?(content) ->
            {acc, bump(skipped, :binary)}

          byte_size(content) > @max_bytes ->
            {acc, bump(skipped, :too_large)}

          true ->
            file = %{
              "path" => path,
              "name" => Path.basename(path),
              "description" => "",
              "content" => content,
              "byte_size" => byte_size(content)
            }

            {[file | acc], skipped}
        end
      end)

    uploaded = Enum.reverse(uploaded)

    merged =
      (existing ++ uploaded)
      |> Enum.reduce(%{}, fn file, acc -> Map.put(acc, file["path"], file) end)
      |> Map.values()
      |> Enum.sort_by(& &1["path"])

    files = normalize_drafts(merged)
    kept = MapSet.new(files, & &1["path"])
    uploaded_kept = Enum.filter(uploaded, &MapSet.member?(kept, &1["path"]))
    added = Enum.count(uploaded_kept, &(not MapSet.member?(existing_paths, &1["path"])))

    stats =
      Map.merge(skipped, %{
        added: added,
        replaced: length(uploaded_kept) - added,
        dropped: length(uploaded) - length(uploaded_kept)
      })

    {files, stats}
  end

  @doc "A sentence for the upload flash."
  def upload_summary(%{} = stats) do
    skipped =
      Map.get(stats, :binary, 0) +
        Map.get(stats, :invalid, 0) +
        Map.get(stats, :ignored, 0) +
        Map.get(stats, :too_large, 0) +
        Map.get(stats, :dropped, 0)

    parts =
      [
        count_part(Map.get(stats, :added, 0), "added"),
        count_part(Map.get(stats, :replaced, 0), "replaced"),
        count_part(skipped, "skipped")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "No reference files were added."
      parts -> "Reference files: " <> Enum.join(parts, ", ") <> "."
    end
  end

  @doc """
  A nested tree for the editor.

  Nodes are maps with `kind: :dir | :file`, `name`, `path`, `children`, and,
  for files, `file` and `index` (the index in the drafts list, used by the form
  field names). Directories sort before files; a blank draft is shown as
  "New file" so the form can open it.
  """
  def tree(files) when is_list(files) do
    files
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {file, index}, root ->
      path = file["path"] || file["name"] || ""
      put_node(root, path_segments(path), file, index)
    end)
    |> to_nodes()
  end

  defp path_segments(""), do: ["New file"]
  defp path_segments(path), do: path |> String.split("/") |> Enum.reject(&(&1 == ""))

  defp put_node(root, [name], file, index) do
    node = Map.get(root, name, %{name: name, children: %{}, file: nil, index: nil})
    Map.put(root, name, %{node | file: file, index: index})
  end

  defp put_node(root, [name | rest], file, index) do
    node = Map.get(root, name, %{name: name, children: %{}, file: nil, index: nil})
    Map.put(root, name, %{node | children: put_node(node.children, rest, file, index)})
  end

  defp to_nodes(map, prefix \\ "") do
    map
    |> Map.values()
    |> Enum.sort_by(fn node -> {node.file != nil, node.name} end)
    |> Enum.map(fn node ->
      path = if prefix == "", do: node.name, else: prefix <> "/" <> node.name
      children = to_nodes(node.children, path)

      %{
        kind: if(node.file && children == [], do: :file, else: :dir),
        name: node.name,
        path: path,
        file: node.file,
        index: node.index,
        children: children
      }
    end)
  end

  @doc "Normalizes a path for storage: forward slashes, no traversal, capped."
  def normalize_path(path) when is_binary(path) do
    path
    |> String.replace("\\", "/")
    |> String.split("/")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", ".", ".."]))
    |> Enum.join("/")
    |> String.slice(0, @max_path)
  end

  def normalize_path(_path), do: ""

  @doc "Hidden files and common build folders are not reference material."
  def ignored_path?(path) when is_binary(path) do
    path
    |> String.split("/")
    |> Enum.any?(fn segment ->
      String.starts_with?(segment, ".") or segment in @ignored_segments
    end)
  end

  def ignored_path?(_path), do: true

  @doc "Whether uploaded bytes are text the agent can read."
  def text_content?(content) when is_binary(content) do
    String.valid?(content) and not String.contains?(content, <<0>>)
  end

  def text_content?(_content), do: false

  defp normalize_draft(file) when is_map(file) do
    raw_path = file |> field_value("path") |> to_text()

    raw_path =
      if String.trim(raw_path) == "", do: file |> field_value("name") |> to_text(), else: raw_path

    path = normalize_path(raw_path)

    description =
      file
      |> field_value("description")
      |> to_text()
      |> String.trim()
      |> String.slice(0, @max_description)

    content = file |> field_value("content") |> to_text() |> clamp_bytes(@max_bytes)

    if path == "" or ignored_path?(path) do
      nil
    else
      %{
        "path" => path,
        "name" => Path.basename(path),
        "description" => description,
        "content" => content,
        "byte_size" => byte_size(content)
      }
    end
  end

  defp normalize_draft(_file), do: nil

  defp take_total_bytes(files) do
    {files, _total} =
      Enum.reduce(files, {[], 0}, fn file, {acc, total} ->
        if total + file["byte_size"] <= @max_total_bytes do
          {acc ++ [file], total + file["byte_size"]}
        else
          {acc, total}
        end
      end)

    files
  end

  defp bump(stats, key), do: Map.update(stats, key, 1, &(&1 + 1))

  defp count_part(0, _label), do: nil
  defp count_part(count, label), do: "#{count} #{label}"

  defp field_value(map, key), do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_number(value) or is_atom(value), do: to_string(value)
  defp to_text(_value), do: ""

  defp clamp_bytes(text, max) do
    if byte_size(text) <= max do
      text
    else
      text |> String.slice(0, max) |> clamp_bytes(max)
    end
  end

  defp scope_field(:template), do: :template_id
  defp scope_field(:canvas), do: :canvas_id
end
