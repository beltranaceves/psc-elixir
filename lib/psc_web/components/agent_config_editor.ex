defmodule PscWeb.Components.AgentConfigEditor do
  @moduledoc """
  The Agent settings form shared by the template designer and the canvas Info
  tab.

  Presentation only: every control emits an `agent_cfg_*` event that the parent
  LiveView applies to its draft. The parent owns persistence, dirty state and
  the template reset.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Agent.Config
  alias Psc.Agent.Files
  alias Psc.Agent.Tools
  alias PscWeb.AgentUploads
  alias PscWeb.Components.MarkdownEditor
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Markdown

  attr :config, :map, required: true
  attr :files, :list, required: true
  attr :uploads, :map, required: true
  attr :id_prefix, :string, required: true
  attr :can_edit?, :boolean, default: false

  # The canvas Info tab saves its section on its own; the designer saves
  # everything with the page-level "Save Template" button.
  attr :show_save?, :boolean, default: false
  attr :show_reset?, :boolean, default: false
  attr :dirty?, :boolean, default: false
  attr :source_name, :string, default: nil
  attr :drift?, :boolean, default: false

  def editor(assigns) do
    upload_preview = AgentUploads.preview(assigns.uploads)

    assigns =
      assigns
      |> assign(:tool_specs, Tools.ui_specs())
      |> assign(:upload_preview, upload_preview)
      |> assign(:upload_file_count, Enum.count(upload_preview, &(&1.kind == :file)))
      |> assign(:upload_pending?, AgentUploads.pending?(assigns.uploads))
      |> assign(:upload_ready?, AgentUploads.ready?(assigns.uploads))

    ~H"""
    <form
      id={"#{@id_prefix}-agent-config"}
      phx-change="agent_cfg_change"
      phx-submit="agent_cfg_form_submit"
      class="space-y-6"
    >
      <div>
        <label
          for={"#{@id_prefix}-agent-prompt"}
          class="block text-xs font-medium uppercase tracking-wide text-base-content/50"
        >
          System prompt
        </label>

        <p class="mt-1 text-xs leading-relaxed text-base-content/50">
          Added to PSC's fixed read-only policy. It can specialize the assistant, but cannot
          grant it new capabilities.
        </p>
        <textarea
          id={"#{@id_prefix}-agent-prompt"}
          name="agent_prompt"
          rows="6"
          phx-debounce="300"
          disabled={!@can_edit?}
          placeholder="For example: you facilitate a problem–solution canvas. Ask one question at a time…"
          class="mt-2 w-full resize-y rounded-lg border border-base-content/15 bg-base-100 px-3 py-2 text-sm leading-6 text-base-content transition-colors placeholder-base-content/35 focus:border-primary focus:outline-none disabled:opacity-60"
        ><%= @config["prompt"] %></textarea>
        <p class="mt-1 text-right text-[11px] text-base-content/40">
          {String.length(@config["prompt"] || "")} / 8000
        </p>
      </div>

      <div>
        <div class="flex items-center justify-between gap-2">
          <div>
            <h3 class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Roles
            </h3>

            <p class="mt-1 text-xs text-base-content/50">
              Named personas the chat can pick before its first message. The default is used
              otherwise.
            </p>
          </div>

          <UIButton.button
            :if={@can_edit?}
            type="button"
            variant="outline"
            size="sm"
            id={"#{@id_prefix}-agent-add-role"}
            phx-click="agent_cfg_add_role"
          >
            <.icon name="hero-plus" class="size-4" /> Add role
          </UIButton.button>
        </div>

        <div id={"#{@id_prefix}-agent-roles"} class="mt-3 space-y-3">
          <p
            :if={(@config["roles"] || []) == []}
            class="rounded-lg border border-dashed border-base-content/20 bg-base-100 px-3 py-2 text-xs text-base-content/50"
          >
            No roles yet. The configured prompt applies by itself.
          </p>

          <div
            :for={role <- @config["roles"] || []}
            id={"#{@id_prefix}-agent-role-#{role["key"]}"}
            class="rounded-lg border border-base-content/10 bg-base-200/60 p-3"
          >
            <div class="flex items-center gap-2">
              <input
                type="text"
                id={"#{@id_prefix}-agent-role-#{role["key"]}-name"}
                name={"role[#{role["key"]}][name]"}
                value={role["name"]}
                phx-debounce="300"
                disabled={!@can_edit?}
                placeholder="Role name"
                class="min-w-0 flex-1 rounded border border-base-content/15 bg-base-100 px-2 py-1 text-sm font-medium text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
              />
              <button
                :if={@can_edit?}
                type="button"
                phx-click="agent_cfg_set_default_role"
                phx-value-key={role["key"]}
                aria-pressed={to_string(@config["default_role"] == role["key"])}
                class={[
                  "shrink-0 rounded-md border px-2 py-1 text-[11px] font-medium transition-colors",
                  @config["default_role"] == role["key"] &&
                    "border-primary/50 bg-primary/10 text-primary",
                  @config["default_role"] != role["key"] &&
                    "border-base-content/15 text-base-content/55 hover:border-base-content/30"
                ]}
              >
                Default
              </button>

              <button
                :if={@can_edit?}
                type="button"
                phx-click="agent_cfg_remove_role"
                phx-value-key={role["key"]}
                title="Remove role"
                aria-label={"Remove role #{role["name"]}"}
                class="shrink-0 rounded-md border border-error/30 p-1 text-error/80 transition-colors hover:bg-error/10"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </div>
            <textarea
              id={"#{@id_prefix}-agent-role-#{role["key"]}-instructions"}
              name={"role[#{role["key"]}][instructions]"}
              rows="3"
              phx-debounce="300"
              disabled={!@can_edit?}
              placeholder="What should this role focus on?"
              class="mt-2 w-full resize-y rounded border border-base-content/15 bg-base-100 px-2 py-1.5 text-xs leading-5 text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
            ><%= role["instructions"] %></textarea>
          </div>
        </div>
      </div>

      <div>
        <div class="flex items-center justify-between gap-2">
          <div>
            <h3 class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Reference files
            </h3>

            <p class="mt-1 text-xs text-base-content/50">
              Text and Markdown documents the agent may read. A template copies them into
              every canvas it creates. At most {Files.max_files()} files, {div(
                Files.max_bytes() + 1023,
                1024
              )} KB each and {div(Files.max_total_bytes() + 1023, 1024)} KB in total. Paths
              are unique.
            </p>
          </div>

          <UIButton.button
            :if={@can_edit? and length(@files) < Files.max_files()}
            type="button"
            variant="outline"
            size="sm"
            id={"#{@id_prefix}-agent-add-file"}
            phx-click="agent_cfg_add_file"
          >
            <.icon name="hero-plus" class="size-4" /> Add file
          </UIButton.button>
        </div>

        <.upload_card
          :if={@can_edit?}
          id_prefix={@id_prefix}
          uploads={@uploads}
          preview={@upload_preview}
          file_count={@upload_file_count}
          pending?={@upload_pending?}
          ready?={@upload_ready?}
        />

        <div id={"#{@id_prefix}-agent-files"} class="mt-3 space-y-1">
          <p
            :if={@files == []}
            class="rounded-lg border border-dashed border-base-content/20 bg-base-100 px-3 py-2 text-xs text-base-content/50"
          >
            No reference files. The manifest is empty and the read tool has nothing to return.
          </p>

          <.file_tree
            :if={@files != []}
            nodes={Files.tree(@files)}
            id_prefix={@id_prefix}
            can_edit?={@can_edit?}
          />
        </div>
      </div>

      <div>
        <h3 class="text-xs font-medium uppercase tracking-wide text-base-content/50">Tools</h3>

        <p class="mt-1 text-xs text-base-content/50">
          The agent can only read. Disabling a tool removes it from the model's tool list for
          chats using this setup.
        </p>

        <div class="mt-3 grid gap-2 sm:grid-cols-2">
          <button
            :for={tool <- @tool_specs}
            type="button"
            id={"#{@id_prefix}-agent-tool-#{tool["name"]}"}
            phx-click="agent_cfg_toggle_tool"
            phx-value-name={tool["name"]}
            disabled={!@can_edit?}
            aria-pressed={to_string(Config.tool_enabled?(@config, tool["name"]))}
            class={[
              "flex items-start gap-2 rounded-lg border p-2.5 text-left transition-colors disabled:opacity-60",
              Config.tool_enabled?(@config, tool["name"]) &&
                "border-primary/40 bg-primary/5",
              !Config.tool_enabled?(@config, tool["name"]) &&
                "border-base-content/10 bg-base-100 opacity-60"
            ]}
          >
            <span class={[
              "mt-0.5 flex size-4 shrink-0 items-center justify-center rounded border",
              Config.tool_enabled?(@config, tool["name"]) &&
                "border-primary bg-primary text-primary-content",
              !Config.tool_enabled?(@config, tool["name"]) && "border-base-content/30"
            ]}>
              <.icon
                :if={Config.tool_enabled?(@config, tool["name"])}
                name="hero-check"
                class="size-3"
              />
            </span>

            <span class="min-w-0">
              <span class="block text-xs font-medium text-base-content">{tool["label"]}</span>
              <span class="mt-0.5 block text-[11px] leading-relaxed text-base-content/50">
                {tool["description"]}
              </span>
            </span>
          </button>
        </div>
      </div>

      <div
        :if={@source_name || @show_save?}
        class="flex flex-wrap items-center gap-3 border-t border-base-content/10 pt-4"
      >
        <p
          :if={@source_name}
          class="min-w-0 flex-1 text-[11px] leading-relaxed text-base-content/50"
        >
          Copied from <span class="font-medium text-base-content/70">{@source_name}</span>.
          <span :if={@drift?} class="text-warning">
            The template's agent settings changed since this canvas was created.
          </span>
          <span>Changes apply to new chats; open chats keep the setup they started with.</span>
        </p>

        <p
          :if={@dirty?}
          id={"#{@id_prefix}-agent-dirty"}
          class="text-xs font-medium text-amber-600 dark:text-amber-300"
        >
          Unsaved changes
        </p>

        <UIButton.button
          :if={@show_reset? and @can_edit?}
          type="button"
          variant="outline"
          id={"#{@id_prefix}-agent-reset"}
          phx-click="agent_cfg_reset"
          data-confirm="Replace this canvas's agent settings and files with the template's current ones?"
        >
          Reset to template
        </UIButton.button>

        <UIButton.button
          :if={@show_save? and @can_edit?}
          type="button"
          id={"#{@id_prefix}-agent-save"}
          phx-click="agent_cfg_save"
        >
          Save agent settings
        </UIButton.button>
      </div>

      <p
        :if={not @show_save?}
        class="text-[11px] leading-relaxed text-base-content/45"
      >
        Saved with the template.
      </p>

      <p class="text-[11px] leading-relaxed text-base-content/45">
        <.icon name="hero-lock-closed" class="mr-1 inline size-3" />
        These instructions are shared with everyone who can use this setup. Reference files
        are sent to each reader's own model provider.
      </p>
    </form>
    """
  end

  attr :nodes, :list, required: true
  attr :id_prefix, :string, required: true
  attr :can_edit?, :boolean, required: true

  defp file_tree(assigns) do
    ~H"""
    <div class="space-y-1">
      <%= for node <- @nodes do %>
        <%= if node.kind == :dir do %>
          <details
            id={"#{@id_prefix}-agent-dir-#{:erlang.phash2(node.path || "")}"}
            open
            phx-hook="DetailsState"
            class="rounded-lg border border-base-content/10 bg-base-200/40"
          >
            <summary class="cursor-pointer px-2.5 py-1.5 text-xs font-medium text-base-content/70">
              <span class="inline-flex items-center gap-1.5">
                <.icon name="hero-folder" class="size-3.5" /> {node.name}
              </span>
            </summary>

            <div class="px-2 pb-2">
              <.file_tree nodes={node.children} id_prefix={@id_prefix} can_edit?={@can_edit?} />
            </div>
          </details>
        <% else %>
          <details
            id={"#{@id_prefix}-agent-file-#{node.index}"}
            phx-hook="DetailsState"
            class="rounded-lg border border-base-content/10 bg-base-200/60"
          >
            <summary class="cursor-pointer px-2.5 py-1.5 text-xs">
              <span class="inline-flex items-center gap-2">
                <.icon
                  name="hero-document-text"
                  class="size-3.5 shrink-0 text-base-content/40"
                />
                <span class="max-w-[24rem] truncate font-mono text-base-content/70">
                  {node.name}
                </span>
                <span class="text-[10px] tabular-nums text-base-content/40">
                  {byte_size_label(node.file["content"])}
                </span>
              </span>
            </summary>

            <div class="space-y-2 border-t border-base-content/10 p-2.5">
              <input
                type="text"
                id={"#{@id_prefix}-agent-file-#{node.index}-path"}
                name={"file[#{node.index}][path]"}
                value={node.file["path"] || node.file["name"]}
                phx-debounce="300"
                disabled={!@can_edit?}
                placeholder="docs/brief.md"
                class="w-full rounded border border-base-content/15 bg-base-100 px-2 py-1 font-mono text-xs font-medium text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
              />

              <input
                type="text"
                id={"#{@id_prefix}-agent-file-#{node.index}-description"}
                name={"file[#{node.index}][description]"}
                value={node.file["description"]}
                phx-debounce="300"
                disabled={!@can_edit?}
                placeholder="One line the model can use to choose this file"
                class="w-full rounded border border-base-content/15 bg-base-100 px-2 py-1 text-xs text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
              />

              <MarkdownEditor.markdown_editor
                id={"#{@id_prefix}-agent-file-md-#{node.index}-#{:erlang.phash2(node.path || "")}"}
                input_id={"#{@id_prefix}-agent-file-#{node.index}-content"}
                form_id={"#{@id_prefix}-agent-file-#{node.index}-editor"}
                preview_id={"#{@id_prefix}-agent-file-#{node.index}-preview"}
                content={node.file["content"] || ""}
                html={
                  node.file["html"] ||
                    Markdown.render(node.file["content"] || "", empty_message: "")
                }
                input_name={"file[#{node.index}][content]"}
                embedded
                change_event="agent_cfg_change"
                preview_event="agent_file_render"
                render_event="agent_file_rendered"
                update_event="agent_file_content_updated"
                preview_label="Edit file content"
                placeholder="Write this file in Markdown…"
                empty_message="No content yet."
                body_class="p-3 font-mono text-xs leading-5"
                class="h-[28rem]"
                hidden_fields={[{"index", node.index}]}
              />

              <div :if={@can_edit?} class="flex justify-end">
                <button
                  type="button"
                  phx-click="agent_cfg_remove_file"
                  phx-value-index={node.index}
                  class="inline-flex items-center gap-1 rounded-md border border-error/30 px-2 py-1 text-[11px] font-medium text-error/80 transition-colors hover:bg-error/10"
                >
                  <.icon name="hero-trash" class="size-3.5" /> Remove file
                </button>
              </div>
            </div>
          </details>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :id_prefix, :string, required: true
  attr :uploads, :map, required: true
  attr :preview, :list, required: true
  attr :file_count, :integer, required: true
  attr :pending?, :boolean, required: true
  attr :ready?, :boolean, required: true

  defp upload_card(assigns) do
    ~H"""
    <div
      id={"#{@id_prefix}-agent-upload"}
      class="rounded-lg border border-dashed border-base-content/20 bg-base-100 p-3"
    >
      <div class="flex flex-wrap items-center gap-2">
        <p class="mr-auto text-xs font-medium text-base-content/70">Add reference files</p>

        <label class="relative inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-base-content/15 bg-base-100 px-2.5 py-1.5 text-xs font-medium text-base-content/70 transition hover:bg-base-200">
          <.live_file_input upload={@uploads.agent_files} class="sr-only" />
          <.icon name="hero-document-plus" class="size-4" /> Choose files
        </label>

        <label class="relative inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-base-content/15 bg-base-100 px-2.5 py-1.5 text-xs font-medium text-base-content/70 transition hover:bg-base-200">
          <.live_file_input upload={@uploads.agent_folder} webkitdirectory class="sr-only" />
          <.icon name="hero-folder-plus" class="size-4" /> Choose folder
        </label>

        <UIButton.button
          type="button"
          id={"#{@id_prefix}-agent-upload-submit"}
          phx-click="agent_cfg_upload"
          variant="outline"
          size="sm"
          class="gap-1.5"
          disabled={@pending? or not @ready?}
        >
          <.icon name="hero-arrow-up-tray" class="size-4" />
          {if @pending?, do: "Uploading…", else: "Add to references"}
        </UIButton.button>
      </div>

      <p class="mt-2 text-[11px] leading-relaxed text-base-content/45">
        Pick specific files or a whole folder. Nested paths are kept. Hidden/build
        folders, binary files and files over {div(Files.max_bytes() + 1023, 1024)} KB are
        skipped; you can remove anything from the preview before adding it.
      </p>

      <div
        :if={@preview != []}
        id={"#{@id_prefix}-agent-upload-preview"}
        class="mt-3 rounded-lg border border-base-content/10 bg-base-200/40 p-2.5"
      >
        <div class="flex items-center justify-between gap-2">
          <p class="text-[11px] font-medium uppercase tracking-wide text-base-content/50">
            Pending files
          </p>
          <span class="text-[11px] text-base-content/40">
            {file_count_label(@file_count)}
          </span>
        </div>

        <div class="mt-2 space-y-0.5 font-mono text-xs leading-5">
          <div :for={row <- @preview} class="flex min-w-0 items-center gap-1">
            <span class="whitespace-pre text-base-content/30">{row.prefix}</span>

            <span class={[
              "truncate",
              row.kind == :dir && "font-semibold text-base-content/70",
              row.kind == :file && "text-base-content/60"
            ]}>
              {row.name}{if row.kind == :dir, do: "/", else: ""}
            </span>

            <span
              :if={row.kind == :file}
              class="shrink-0 text-[10px] tabular-nums text-base-content/35"
            >
              {format_bytes(row.size)}
            </span>

            <span :if={row.kind == :file and not row.valid?} class="shrink-0 text-[10px] text-error">
              invalid
            </span>

            <span
              :if={row.kind == :file and row.valid? and not row.done?}
              class="shrink-0 text-[10px] text-base-content/35"
            >
              uploading…
            </span>

            <span class="shrink-0">
              <button
                :if={row.kind == :dir}
                type="button"
                phx-click="agent_cfg_cancel_directory"
                phx-value-path={row.path}
                aria-label={"Remove #{row.name}"}
                class="ml-1 rounded p-0.5 text-base-content/30 transition-colors hover:bg-error/10 hover:text-error"
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>

              <button
                :if={row.kind == :file}
                type="button"
                phx-click="agent_cfg_cancel_upload"
                phx-value-upload={row.upload}
                phx-value-ref={row.ref}
                aria-label={"Remove #{row.name}"}
                class="ml-1 rounded p-0.5 text-base-content/30 transition-colors hover:bg-error/10 hover:text-error"
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp file_count_label(1), do: "1 file"
  defp file_count_label(count), do: "#{count} files"

  defp byte_size_label(content) do
    content
    |> to_string()
    |> byte_size()
    |> format_bytes()
  end

  defp format_bytes(size) when size < 1024, do: "#{size} B"
  defp format_bytes(size), do: "#{Float.round(size / 1024, 1)} KB"
end
