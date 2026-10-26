defmodule PscWeb.AgentUploads do
  @moduledoc """
  The staged reference-file upload.

  Two pickers feed one staging area: individual files and a folder (whose
  relative paths are preserved). A README-style preview shows the pending tree
  before anything is added to the canvas, with per-file and per-directory
  removal. Only "Add to references" consumes the uploads into the editor draft.
  """

  alias Psc.Agent.Files
  alias PscWeb.Markdown

  @upload_names [:agent_files, :agent_folder]

  def upload_names, do: @upload_names

  def allow(socket) do
    Enum.reduce(@upload_names, socket, fn name, socket ->
      Phoenix.LiveView.allow_upload(socket, name,
        accept: :any,
        max_entries: Files.max_upload_entries(),
        max_file_size: Files.max_bytes(),
        # The preview is useful only once the entries exist on the server; the
        # bytes land in a temp file, which is not the reference list. Nothing is
        # merged into the canvas until "Add to references".
        auto_upload: true
      )
    end)
  end

  @doc "The staged entries of both pickers, with normalized paths."
  def entries(uploads) when is_map(uploads) do
    Enum.flat_map(@upload_names, fn name ->
      case Map.get(uploads, name) do
        %{entries: entries} -> Enum.map(entries, &to_info(&1, name))
        _other -> []
      end
    end)
  end

  def pending?(uploads) when is_map(uploads) do
    # Invalid entries never become done; they must not keep the submit button
    # disabled forever.
    Enum.any?(entries(uploads), &(&1.valid? and not &1.done?))
  end

  def ready?(uploads) when is_map(uploads) do
    Enum.any?(entries(uploads), &(&1.valid? and &1.done?))
  end

  @doc """
  A flattened, README-style preview tree.

  Rows are `%{kind: :dir | :file, name, path, prefix, upload, ref, size,
  valid?, done?}`. Hidden/build paths are not shown; they would be skipped on
  merge anyway.
  """
  def preview(uploads) when is_map(uploads) do
    uploads
    |> entries()
    |> Enum.reject(&Files.ignored_path?(&1.path))
    |> build_preview()
  end

  def cancel(socket, upload, ref) do
    case upload_name(upload) do
      nil -> socket
      name -> Phoenix.LiveView.cancel_upload(socket, name, ref)
    end
  end

  def cancel_directory(socket, path) when is_binary(path) do
    prefix = path <> "/"

    socket.assigns.uploads
    |> entries()
    |> Enum.filter(fn entry -> entry.path == path or String.starts_with?(entry.path, prefix) end)
    |> Enum.reduce(socket, fn entry, socket -> cancel(socket, entry.upload, entry.ref) end)
  end

  def cancel_directory(socket, _path), do: socket

  @doc "Adds the rendered Markdown used by the file editor's initial preview."
  def with_html(files) when is_list(files) do
    Enum.map(files, fn file ->
      Map.put_new_lazy(file, "html", fn ->
        Markdown.render(file["content"] || "", empty_message: "")
      end)
    end)
  end

  @doc "Consumes both pickers and merges them into the current drafts."
  def apply(socket, current_files) do
    {uploads, invalid} = consume(socket)

    {files, stats} = Files.merge_uploads(current_files, uploads)
    {with_html(files), Map.update(stats, :invalid, invalid, &(&1 + invalid))}
  end

  defp consume(socket) do
    staged = entries(socket.assigns.uploads)
    invalid = Enum.count(staged, &(not &1.valid?))

    uploads =
      staged
      |> Enum.filter(&(&1.valid? and &1.done?))
      |> Enum.map(fn info ->
        Phoenix.LiveView.consume_uploaded_entry(socket, info.entry, fn %{path: path} ->
          {:ok, %{"path" => info.path, "content" => File.read!(path)}}
        end)
      end)

    {uploads, invalid}
  end

  defp to_info(entry, upload) do
    %{
      upload: upload,
      entry: entry,
      ref: entry.ref,
      path: Files.normalize_path(relative_path(entry)),
      name: entry.client_name,
      size: entry.client_size || 0,
      valid?: entry.valid?,
      done?: entry.done?,
      progress: entry.progress
    }
  end

  defp relative_path(entry) do
    case entry.client_relative_path do
      path when is_binary(path) and path != "" -> path
      _other -> entry.client_name
    end
  end

  ## Preview tree

  defp build_preview(entries) do
    entries
    |> Enum.reduce(%{}, fn entry, tree ->
      put(tree, String.split(entry.path, "/"), entry)
    end)
    |> flatten("", "", [])
    |> Enum.reverse()
  end

  defp put(tree, [name], entry) do
    Map.put(tree, name, %{kind: :file, name: name, entry: entry, children: %{}})
  end

  defp put(tree, [name | rest], entry) do
    node = Map.get(tree, name, %{kind: :dir, name: name, entry: nil, children: %{}})
    node = %{node | children: put(node.children, rest, entry)}
    Map.put(tree, name, node)
  end

  defp flatten(tree, prefix, path, acc) do
    nodes =
      tree
      |> Map.values()
      |> Enum.sort_by(fn node -> {node.kind == :file, node.name} end)

    nodes
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {node, index}, acc ->
      last? = index == length(nodes) - 1
      connector = if last?, do: "└── ", else: "├── "
      node_path = if path == "", do: node.name, else: path <> "/" <> node.name

      row = %{
        kind: node.kind,
        name: node.name,
        path: node_path,
        prefix: prefix <> connector,
        upload: node.entry && node.entry.upload,
        ref: node.entry && node.entry.ref,
        size: node.entry && node.entry.size,
        valid?: node.entry && node.entry.valid?,
        done?: node.entry && node.entry.done?
      }

      acc = [row | acc]

      if node.kind == :dir do
        child_prefix = prefix <> if(last?, do: "    ", else: "│   ")
        flatten(node.children, child_prefix, node_path, acc)
      else
        acc
      end
    end)
  end

  defp upload_name(name) when name in @upload_names, do: name

  defp upload_name(name) when is_binary(name) do
    Enum.find(@upload_names, &(Atom.to_string(&1) == name))
  end

  defp upload_name(_name), do: nil
end
