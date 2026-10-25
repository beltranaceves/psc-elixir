defmodule PscWeb.UserLive.SettingsAgentConnections do
  @moduledoc """
  The "Agent connections" section of the settings page: the list of saved
  connections and the add/edit dialog.

  Presentation only. The events it emits (`new_connection`, `edit_connection`,
  `set_default_connection`, `delete_connection`, `select_provider`,
  `save_connection`, `close_connection_dialog`) are handled by
  `PscWeb.UserLive.Settings`, which owns the dialog state machine and the
  provider probe.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Agent.Connection
  alias Psc.Agent.ModelCatalog
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.UI.Form, as: UIForm
  alias PscWeb.Components.UI.Input, as: UIInput

  @doc """
  Builds the state the dialog renders from, for a connection or a blank form.

  Offline model suggestions come from the packaged catalog; a test round trip
  can replace them with the provider's live list.
  """
  def dialog_state(connection) do
    provider = (connection && connection.provider) || "openai"

    models =
      case connection && connection.models do
        models when is_list(models) and models != [] -> models
        _other -> ModelCatalog.suggestions(provider)
      end

    %{
      connection: connection,
      provider: provider,
      provider_open: false,
      models: models,
      test: nil,
      tested_for: nil,
      pending_key: nil,
      form: to_form(Connection.changeset(connection || %Connection{}, %{}), as: :connection)
    }
  end

  attr :connections, :list, required: true

  def connections(assigns) do
    ~H"""
    <div id="agent-connections" class="mt-6 rounded-xl border border-base-content/10 bg-base-200 p-6">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h3 class="text-lg font-medium text-base-content">Agent connections</h3>

          <p class="mt-1 text-sm text-base-content/60">
            The canvas agent answers through one of these. Each connection holds a provider
            key and the model it should call.
          </p>
        </div>

        <UIButton.button type="button" phx-click="new_connection" class="shrink-0">
          <.icon name="hero-plus" class="size-4" /> New
        </UIButton.button>
      </div>

      <div
        :if={@connections == []}
        class="mt-4 rounded-xl border border-dashed border-base-content/20 bg-base-100 p-5 text-center"
      >
        <p class="text-sm font-medium text-base-content">No connections yet</p>

        <p class="mt-1 text-xs leading-relaxed text-base-content/55">
          Add a provider key and a model to turn the canvas agent on.
        </p>

        <UIButton.button type="button" phx-click="new_connection" class="mt-3">
          Add your first connection
        </UIButton.button>
      </div>

      <div :if={@connections != []} class="mt-4 space-y-2">
        <.connection_row :for={connection <- @connections} connection={connection} />
      </div>
    </div>
    """
  end

  attr :dialog, :map, default: nil
  attr :providers, :list, required: true

  def dialog(assigns) do
    ~H"""
    <UIDialog.dialog
      :if={@dialog}
      id="connection-dialog"
      open
      on-close="close_connection_dialog"
    >
      <UIDialog.dialog_content open class="sm:max-w-lg">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>
            {if @dialog.connection, do: "Edit connection", else: "New connection"}
          </UIDialog.dialog_title>

          <UIDialog.dialog_description>
            The key is stored for your account only and never rendered back.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <.form
          for={@dialog.form}
          id="connection-form"
          phx-submit="save_connection"
          class="space-y-3"
        >
          <UIForm.form_item>
            <UIForm.form_label field={@dialog.form[:name]}>Name</UIForm.form_label>

            <UIForm.form_control>
              <UIInput.input
                field={@dialog.form[:name]}
                required
                maxlength="40"
                autocomplete="off"
                placeholder="Work OpenAI"
              />
            </UIForm.form_control>
            <UIForm.form_message field={@dialog.form[:name]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@dialog.form[:provider]}>Provider</UIForm.form_label>

            <UIForm.form_control>
              <div
                id="connection-provider-field"
                class="relative"
                phx-hook="ProviderSelect"
                phx-click-away="close_provider_list"
              >
                <input type="hidden" name={@dialog.form[:provider].name} value={@dialog.provider} />

                <button
                  type="button"
                  id={@dialog.form[:provider].id}
                  phx-click="toggle_provider_list"
                  aria-haspopup="listbox"
                  aria-expanded={to_string(@dialog.provider_open)}
                  aria-controls="connection-provider-list"
                  aria-label={"Provider: " <> Connection.provider_label(@dialog.provider)}
                  class="flex h-10 w-full items-center justify-between gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground shadow-xs transition-colors focus:outline-hidden focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]"
                >
                  <span class="truncate">{Connection.provider_label(@dialog.provider)}</span>
                  <.icon
                    name="hero-chevron-down"
                    class="size-4 shrink-0 text-muted-foreground"
                  />
                </button>

                <div
                  :if={@dialog.provider_open}
                  id="connection-provider-list"
                  role="listbox"
                  aria-label="Providers"
                  class="absolute inset-x-0 top-full z-30 mt-1 max-h-64 overflow-y-auto overscroll-contain rounded-xl border border-base-content/10 bg-base-100 p-1 shadow-xl"
                >
                  <button
                    :for={provider <- @providers}
                    type="button"
                    role="option"
                    aria-selected={to_string(provider.id == @dialog.provider)}
                    phx-click="select_provider"
                    phx-value-provider={provider.id}
                    class={[
                      "flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm transition-colors",
                      if(provider.id == @dialog.provider,
                        do: "bg-primary/10 text-primary",
                        else: "text-base-content/80 hover:bg-base-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-check"
                      class={["size-4 shrink-0", provider.id != @dialog.provider && "invisible"]}
                    />
                    <span class="truncate">{provider.label}</span>
                  </button>
                </div>
              </div>
            </UIForm.form_control>
            <UIForm.form_message field={@dialog.form[:provider]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@dialog.form[:model_id]}>Model</UIForm.form_label>

            <UIForm.form_control>
              <div id="connection-model-field" phx-hook="ModelSuggestions" class="relative">
                <UIInput.input
                  field={@dialog.form[:model_id]}
                  required
                  maxlength="120"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder={model_placeholder(@dialog)}
                />

                <div
                  id="connection-model-suggestions"
                  data-suggestions
                  role="listbox"
                  aria-label="Model suggestions"
                  hidden
                  class="absolute inset-x-0 top-full z-30 mt-1 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-xl"
                >
                  <div class="flex items-center justify-between border-b border-base-content/10 px-3 py-2">
                    <span class="text-[11px] font-medium uppercase tracking-wider text-base-content/40">
                      Models
                    </span>
                    <span data-suggestions-count class="text-[11px] text-base-content/40">
                      {length(@dialog.models)}
                    </span>
                  </div>

                  <div class="max-h-56 overflow-y-auto overscroll-contain p-1">
                    <button
                      :for={model <- @dialog.models}
                      type="button"
                      role="option"
                      tabindex="-1"
                      data-suggestion={model}
                      class="block w-full truncate rounded-lg px-2.5 py-2 text-left text-sm text-base-content/80 transition-colors hover:bg-base-200 data-[active=true]:bg-primary/10 data-[active=true]:text-primary"
                    >
                      {model}
                    </button>

                    <p
                      data-suggestions-empty
                      hidden
                      class="px-2.5 py-3 text-sm text-base-content/50"
                    >
                      No matching models.
                    </p>
                  </div>
                </div>
              </div>
            </UIForm.form_control>
            <p class="mt-1 text-xs text-base-content/45">
              Start typing to filter suggestions, or test the connection to fetch this provider's
              list.
            </p>
            <UIForm.form_message field={@dialog.form[:model_id]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@dialog.form[:api_key]}>API key</UIForm.form_label>

            <UIForm.form_control>
              <%!-- `value=""` is deliberate: binding the field alone would render
              the saved key back into the HTML. The key is write-only. --%>
              <UIInput.input
                field={@dialog.form[:api_key]}
                value=""
                type="password"
                autocomplete="off"
                spellcheck="false"
                placeholder={key_placeholder(@dialog)}
              />
            </UIForm.form_control>

            <p class="mt-1 text-xs text-base-content/45">{key_help(@dialog)}</p>
            <UIForm.form_message field={@dialog.form[:api_key]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@dialog.form[:base_url]}>
              Base URL <span class="text-base-content/40">(optional)</span>
            </UIForm.form_label>

            <UIForm.form_control>
              <UIInput.input
                field={@dialog.form[:base_url]}
                autocomplete="off"
                spellcheck="false"
                placeholder={base_url_placeholder(@dialog)}
              />
            </UIForm.form_control>

            <p class="mt-1 text-xs text-base-content/45">
              For self-hosted servers and OpenAI-compatible gateways.
            </p>
            <UIForm.form_message field={@dialog.form[:base_url]} />
          </UIForm.form_item>

          <div
            :if={@dialog.test}
            id="connection-test-result"
            class={[
              "rounded-lg border px-3 py-2 text-xs leading-relaxed",
              test_class(@dialog.test)
            ]}
          >
            {@dialog.test.message}
          </div>

          <UIDialog.dialog_footer class="sm:justify-between">
            <button
              type="submit"
              name="action"
              value="test"
              phx-disable-with="Testing…"
              class="rounded-lg border border-base-content/20 px-3 py-2 text-sm font-medium text-base-content/80 transition hover:bg-base-200 disabled:opacity-50"
            >
              Test connection
            </button>

            <div class="flex gap-2">
              <UIButton.button type="button" variant="outline" phx-click="close_connection_dialog">
                Cancel
              </UIButton.button>

              <UIButton.button type="submit" name="action" value="save" phx-disable-with="Saving…">
                Save connection
              </UIButton.button>
            </div>
          </UIDialog.dialog_footer>
        </.form>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  attr :connection, :map, required: true

  defp connection_row(assigns) do
    ~H"""
    <div
      id={"connection-" <> @connection.id}
      class={[
        "flex items-start gap-3 rounded-xl border bg-base-100 p-3",
        if(@connection.default?, do: "border-primary/40", else: "border-base-content/10")
      ]}
    >
      <input
        type="radio"
        id={"default-connection-" <> @connection.id}
        name="default_connection"
        value={@connection.id}
        checked={@connection.default?}
        phx-click="set_default_connection"
        phx-value-connection={@connection.id}
        aria-label={"Make #{@connection.name} the default"}
        class="mt-1 size-4 shrink-0 accent-primary"
      />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <p class="truncate text-sm font-medium text-base-content">{@connection.name}</p>

          <span
            :if={@connection.default?}
            class="shrink-0 rounded-full bg-primary/15 px-1.5 py-0.5 text-[10px] font-medium text-primary"
          >
            Default
          </span>
        </div>

        <p class="mt-0.5 truncate text-xs text-base-content/55">
          {@connection.provider_label} · {@connection.model_id}
        </p>

        <p class="mt-0.5 truncate text-[11px] text-base-content/40">
          {if @connection.key_hint, do: "key " <> @connection.key_hint, else: "no key"}
          <span :if={@connection.base_url}> · {@connection.base_url}</span>
        </p>
      </div>

      <details data-menu class="relative shrink-0">
        <summary class="flex size-8 cursor-pointer list-none items-center justify-center rounded-lg text-base-content/50 hover:bg-base-200 [&::-webkit-details-marker]:hidden">
          <.icon name="hero-ellipsis-horizontal" class="size-4" />
        </summary>

        <div class="absolute right-0 z-20 mt-1 w-32 rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-lg">
          <button
            type="button"
            id={"edit-connection-" <> @connection.id}
            phx-click="edit_connection"
            phx-value-connection={@connection.id}
            class="w-full rounded px-2 py-1.5 text-left text-xs hover:bg-base-200"
          >
            Edit
          </button>

          <button
            type="button"
            id={"delete-connection-" <> @connection.id}
            phx-click="delete_connection"
            phx-value-connection={@connection.id}
            data-confirm={"Delete #{@connection.name}?"}
            class="w-full rounded px-2 py-1.5 text-left text-xs text-error hover:bg-error/10"
          >
            Delete
          </button>
        </div>
      </details>
    </div>
    """
  end

  defp model_placeholder(dialog) do
    case Connection.provider_meta(dialog.provider) do
      %{model_placeholder: placeholder} -> placeholder
      nil -> ""
    end
  end

  defp base_url_placeholder(dialog) do
    Connection.default_base_url(dialog.provider) || "https://…"
  end

  defp key_placeholder(dialog) do
    if dialog.connection && dialog.connection.key_hint do
      "•••••••• (saved)"
    else
      case Connection.provider_meta(dialog.provider) do
        %{key_placeholder: placeholder} -> placeholder
        nil -> "API key"
      end
    end
  end

  defp key_help(dialog) do
    help =
      cond do
        dialog.connection && dialog.connection.key_hint ->
          "A key is saved (#{dialog.connection.key_hint}). Leave it blank to keep it, or type a new one to replace it."

        Connection.needs_key?(dialog.provider) ->
          "Stored for your account only. Never shown again after you save it."

        true ->
          "Not required for this provider."
      end

    if dialog.pending_key do
      help <> " The key you typed is kept for this save."
    else
      help
    end
  end

  defp test_class(%{status: :ok}), do: "border-success/30 bg-success/10 text-success"
  defp test_class(_test), do: "border-error/30 bg-error/10 text-error"
end
