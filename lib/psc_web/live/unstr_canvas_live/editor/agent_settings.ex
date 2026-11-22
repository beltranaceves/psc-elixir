defmodule PscWeb.UnstrCanvasLive.Editor.AgentSettings do
  @moduledoc """
  The canvas's agent setup on the Info tab: prompt, roles, tools and reference
  files, edited as a draft and saved together. Also reloads the setup when a
  collaborator saves it in another tab.
  """
  use PscWeb, :html
  import Phoenix.LiveView

  alias Psc.Agent.Config, as: AgentConfig
  alias Psc.Agent.Files, as: AgentFiles
  alias Psc.Canvas
  alias PscWeb.AgentUploads
  alias PscWeb.Markdown

  @doc "Adds the agent setup's assigns and uploads, and registers its hooks."
  def attach(socket) do
    canvas = socket.assigns.canvas
    source = Canvas.agent_source_template(canvas)

    socket
    |> assign(:agent_config, AgentConfig.normalize(canvas.agent_config))
    |> assign(:agent_files, AgentFiles.drafts(:canvas, canvas.id) |> AgentUploads.with_html())
    |> assign(:agent_config_dirty?, false)
    |> assign(:agent_source_template, source)
    |> assign(:agent_config_drift?, Canvas.agent_config_drift?(canvas, source))
    |> AgentUploads.allow()
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
    |> attach_hook(__MODULE__, :handle_info, &handle_info/2)
  end

  # ─── Canvas agent settings (Info tab) ───

  def handle_event("agent_cfg_change", %{"_target" => target} = params, socket) do
    {:halt,
     socket
     |> update_agent_config(&AgentConfig.apply_form_change(&1, target, params))
     |> assign(
       :agent_files,
       AgentFiles.apply_form_change(socket.assigns.agent_files, target, params)
     )}
  end

  def handle_event("agent_cfg_change", _params, socket), do: {:halt, socket}

  def handle_event("agent_cfg_cancel_upload", %{"upload" => upload, "ref" => ref}, socket) do
    {:halt, AgentUploads.cancel(socket, upload, ref)}
  end

  def handle_event("agent_cfg_cancel_directory", %{"path" => path}, socket) do
    {:halt, AgentUploads.cancel_directory(socket, path)}
  end

  def handle_event("agent_cfg_upload", _params, socket) do
    cond do
      AgentUploads.pending?(socket.assigns.uploads) ->
        {:halt, put_flash(socket, :info, "Files are still uploading. Try again in a moment.")}

      not AgentUploads.ready?(socket.assigns.uploads) ->
        {:halt, socket}

      true ->
        {files, stats} = AgentUploads.apply(socket, socket.assigns.agent_files)
        socket = update_agent_files(socket, fn _files -> files end)

        {:halt, put_flash(socket, :info, AgentFiles.upload_summary(stats))}
    end
  end

  def handle_event("agent_file_render", %{"index" => index, "content" => content}, socket)
      when is_binary(content) do
    with {index, ""} <- Integer.parse(to_string(index)),
         true <- index >= 0 and index < length(socket.assigns.agent_files) do
      html = Markdown.render(content, empty_message: "")
      files = List.update_at(socket.assigns.agent_files, index, &Map.put(&1, "html", html))

      {:halt,
       socket
       |> assign(:agent_files, files)
       |> push_event("agent_file_rendered", %{content: content, html: html})}
    else
      _other -> {:halt, socket}
    end
  end

  def handle_event("agent_file_render", _params, socket), do: {:halt, socket}

  def handle_event("agent_cfg_add_role", _params, socket) do
    {:halt, update_agent_config(socket, &AgentConfig.add_role/1)}
  end

  def handle_event("agent_cfg_remove_role", %{"key" => key}, socket) do
    {:halt, update_agent_config(socket, &AgentConfig.remove_role(&1, key))}
  end

  def handle_event("agent_cfg_set_default_role", %{"key" => key}, socket) do
    {:halt, update_agent_config(socket, &AgentConfig.set_default_role(&1, key))}
  end

  def handle_event("agent_cfg_toggle_tool", %{"name" => name}, socket) do
    {:halt, update_agent_config(socket, &AgentConfig.toggle_tool(&1, name))}
  end

  def handle_event("agent_cfg_add_file", _params, socket) do
    if length(socket.assigns.agent_files) < AgentFiles.max_files() do
      {:halt, update_agent_files(socket, &(&1 ++ [AgentFiles.blank_draft()]))}
    else
      {:halt, put_flash(socket, :error, "At most #{AgentFiles.max_files()} reference files.")}
    end
  end

  def handle_event("agent_cfg_remove_file", %{"index" => index}, socket) do
    case parse_index(index) do
      nil ->
        {:halt, socket}

      index ->
        {:halt, update_agent_files(socket, &List.delete_at(&1, index))}
    end
  end

  def handle_event("agent_cfg_save", _params, socket) do
    {:halt, save_agent_config(socket)}
  end

  # Enter in one of the section's text fields submits its form; saving is the
  # least surprising outcome on the canvas.
  def handle_event("agent_cfg_form_submit", _params, socket) do
    {:halt, save_agent_config(socket)}
  end

  def handle_event("agent_cfg_reset", _params, socket) do
    case Canvas.reset_agent_config(socket.assigns.canvas) do
      {:ok, canvas} ->
        {:halt,
         socket
         |> assign(:canvas, canvas)
         |> reload_agent_config()
         |> put_flash(:success, "Agent settings reset to the template")}

      {:error, :no_template} ->
        {:halt, put_flash(socket, :error, "The source template is no longer available")}

      {:error, _reason} ->
        {:halt, put_flash(socket, :error, "Could not reset the agent settings")}
    end
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # Re-reads the saved agent setup after a save or a collaborator's broadcast.
  # The draft is replaced on purpose: the database is the source of truth.
  defp reload_agent_config(socket) do
    canvas =
      Psc.Canvas.get_unstr_canvas_with_author(socket.assigns.canvas.id) || socket.assigns.canvas

    config = AgentConfig.normalize(canvas.agent_config)
    source = Canvas.agent_source_template(canvas)

    role =
      case socket.assigns[:agent_session] do
        %{role: role} when is_binary(role) -> role
        _other -> config["default_role"]
      end

    socket
    |> assign(:canvas, canvas)
    |> assign(:agent_config, config)
    |> assign(:agent_files, AgentFiles.drafts(:canvas, canvas.id) |> AgentUploads.with_html())
    |> assign(:agent_config_dirty?, false)
    |> assign(:agent_source_template, source)
    |> assign(:agent_config_drift?, Canvas.agent_config_drift?(canvas, source))
    |> assign(:agent_roles, config["roles"] || [])
    |> assign(:agent_role, role)
  end

  defp save_agent_config(socket) do
    case Canvas.update_agent_config(
           socket.assigns.canvas,
           socket.assigns.agent_config,
           socket.assigns.agent_files
         ) do
      {:ok, canvas} ->
        socket
        |> assign(:canvas, canvas)
        |> reload_agent_config()
        |> put_flash(:success, "Agent settings saved")

      {:error, _reason} ->
        put_flash(socket, :error, "Could not save the agent settings")
    end
  end

  defp update_agent_config(socket, fun) do
    socket
    |> assign(:agent_config, fun.(socket.assigns.agent_config))
    |> assign(:agent_config_dirty?, true)
  end

  defp update_agent_files(socket, fun) do
    socket
    |> assign(:agent_files, fun.(socket.assigns.agent_files))
    |> assign(:agent_config_dirty?, true)
  end

  defp parse_index(value) when is_integer(value), do: value

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> index
      _other -> nil
    end
  end

  defp parse_index(_value), do: nil

  def handle_info({:agent_config_updated, canvas_id}, socket) do
    cond do
      socket.assigns.canvas_id != canvas_id ->
        {:halt, socket}

      socket.assigns.agent_config_dirty? ->
        {:halt,
         put_flash(
           socket,
           :info,
           "Agent settings were updated in another tab. Save yours to overwrite them."
         )}

      true ->
        {:halt, reload_agent_config(socket)}
    end
  end

  def handle_info(_message, socket), do: {:cont, socket}
end
