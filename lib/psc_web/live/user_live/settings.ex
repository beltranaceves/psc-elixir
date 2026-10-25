defmodule PscWeb.UserLive.Settings do
  use PscWeb, :live_view

  on_mount {PscWeb.UserAuth, :require_sudo_mode}

  # SaladUI button/input/form called qualified (UIButton/UIInput/UIForm):
  # CoreComponents is global via html_helpers and defines the same names.
  alias Psc.Agent.Connection
  alias Psc.Agent.Connections
  alias Psc.Agent.ModelCatalog
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Form, as: UIForm
  alias PscWeb.Components.UI.Input, as: UIInput

  alias Psc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} header_title="Settings">
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Account Settings
            <:subtitle>Manage your account email address and password settings</:subtitle>
          </.header>
        </div>

        <.form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <UIForm.form_item>
            <UIForm.form_label field={@email_form[:email]}>Email</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@email_form[:email]}
                type="email"
                autocomplete="username"
                spellcheck="false"
                placeholder="you@example.com"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={@email_form[:email]} />
          </UIForm.form_item>
          <UIButton.button phx-disable-with="Changing..." class="w-full mt-3">
            Change Email
          </UIButton.button>
        </.form>

        <div class="h-px bg-base-content/10" />

        <.form
          for={@password_form}
          id="password_form"
          action={~p"/users/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            spellcheck="false"
            value={@current_email}
          />
          <UIForm.form_item>
            <UIForm.form_label field={@password_form[:password]}>
              New password
            </UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@password_form[:password]}
                type="password"
                autocomplete="new-password"
                spellcheck="false"
                placeholder="At least 12 characters"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={@password_form[:password]} />
          </UIForm.form_item>
          <UIForm.form_item>
            <UIForm.form_label field={@password_form[:password_confirmation]}>
              Confirm new password
            </UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@password_form[:password_confirmation]}
                type="password"
                autocomplete="new-password"
                spellcheck="false"
                placeholder="Repeat your password"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={@password_form[:password_confirmation]} />
          </UIForm.form_item>
          <UIButton.button phx-disable-with="Saving..." class="w-full mt-3">
            Save Password
          </UIButton.button>
        </.form>
      </div>

      <div
        id="agent-connections"
        class="mt-6 rounded-xl border border-base-content/10 bg-base-200 p-6"
      >
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

      <UIDialog.dialog
        :if={@connection_dialog}
        id="connection-dialog"
        open
        on-close="close_connection_dialog"
      >
        <UIDialog.dialog_content class="sm:max-w-lg">
          <UIDialog.dialog_header>
            <UIDialog.dialog_title>
              {if @connection_dialog.connection, do: "Edit connection", else: "New connection"}
            </UIDialog.dialog_title>

            <UIDialog.dialog_description>
              The key is stored for your account only and never rendered back.
            </UIDialog.dialog_description>
          </UIDialog.dialog_header>

          <.form
            for={@connection_dialog.form}
            id="connection-form"
            phx-submit="save_connection"
            class="space-y-3"
          >
            <UIForm.form_item>
              <UIForm.form_label field={@connection_dialog.form[:name]}>Name</UIForm.form_label>
              <UIForm.form_control>
                <UIInput.input
                  field={@connection_dialog.form[:name]}
                  required
                  maxlength="40"
                  autocomplete="off"
                  placeholder="Work OpenAI"
                />
              </UIForm.form_control>
              <UIForm.form_message field={@connection_dialog.form[:name]} />
            </UIForm.form_item>

            <UIForm.form_item>
              <UIForm.form_label field={@connection_dialog.form[:provider]}>
                Provider
              </UIForm.form_label>
              <UIForm.form_control>
                <select
                  name={@connection_dialog.form[:provider].name}
                  id={@connection_dialog.form[:provider].id}
                  phx-change="select_provider"
                  class="w-full rounded-lg border border-base-content/20 bg-base-100 px-3 py-2 text-sm"
                >
                  <option
                    :for={provider <- @providers}
                    value={provider.id}
                    selected={provider.id == @connection_dialog.provider}
                  >
                    {provider.label}
                  </option>
                </select>
              </UIForm.form_control>
              <UIForm.form_message field={@connection_dialog.form[:provider]} />
            </UIForm.form_item>

            <UIForm.form_item>
              <UIForm.form_label field={@connection_dialog.form[:model_id]}>Model</UIForm.form_label>
              <UIForm.form_control>
                <UIInput.input
                  field={@connection_dialog.form[:model_id]}
                  list="connection-models"
                  required
                  maxlength="120"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder={model_placeholder(@connection_dialog)}
                />
              </UIForm.form_control>
              <datalist id="connection-models">
                <option :for={model <- @connection_dialog.models} value={model}></option>
              </datalist>
              <p class="mt-1 text-xs text-base-content/45">
                Start typing for suggestions, or test the connection to fetch this provider's list.
              </p>
              <UIForm.form_message field={@connection_dialog.form[:model_id]} />
            </UIForm.form_item>

            <UIForm.form_item>
              <UIForm.form_label field={@connection_dialog.form[:api_key]}>API key</UIForm.form_label>
              <UIForm.form_control>
                <%!-- `value=""` is deliberate: binding the field alone would render
                the saved key back into the HTML. The key is write-only. --%>
                <UIInput.input
                  field={@connection_dialog.form[:api_key]}
                  value=""
                  type="password"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder={key_placeholder(@connection_dialog)}
                />
              </UIForm.form_control>
              <p class="mt-1 text-xs text-base-content/45">{key_help(@connection_dialog)}</p>
              <UIForm.form_message field={@connection_dialog.form[:api_key]} />
            </UIForm.form_item>

            <UIForm.form_item>
              <UIForm.form_label field={@connection_dialog.form[:base_url]}>
                Base URL <span class="text-base-content/40">(optional)</span>
              </UIForm.form_label>
              <UIForm.form_control>
                <UIInput.input
                  field={@connection_dialog.form[:base_url]}
                  autocomplete="off"
                  spellcheck="false"
                  placeholder={base_url_placeholder(@connection_dialog)}
                />
              </UIForm.form_control>
              <p class="mt-1 text-xs text-base-content/45">
                For self-hosted servers and OpenAI-compatible gateways.
              </p>
              <UIForm.form_message field={@connection_dialog.form[:base_url]} />
            </UIForm.form_item>

            <div
              :if={@connection_dialog.test}
              id="connection-test-result"
              class={[
                "rounded-lg border px-3 py-2 text-xs leading-relaxed",
                test_class(@connection_dialog.test)
              ]}
            >
              {@connection_dialog.test.message}
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
                <UIButton.button
                  type="button"
                  variant="outline"
                  phx-click="close_connection_dialog"
                >
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
    </Layouts.app>
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

  ## Agent connections

  defp connection_dialog_state(connection) do
    provider = (connection && connection.provider) || "openai"

    models =
      case connection && connection.models do
        models when is_list(models) and models != [] -> models
        _other -> ModelCatalog.suggestions(provider)
      end

    %{
      connection: connection,
      provider: provider,
      models: models,
      test: nil,
      tested_for: nil,
      pending_key: nil,
      form: to_form(Connection.changeset(connection || %Connection{}, %{}), as: :connection)
    }
  end

  defp refresh_connections(socket) do
    assign(socket, :connections, Connections.summaries(socket.assigns.current_scope.user.id))
  end

  defp test_connection(dialog, params) do
    provider = params["provider"] || dialog.provider
    base_url = test_base_url(params)
    key = test_key(params, dialog.connection)

    {test, models, tested_for} = run_connection_test(provider, key, base_url, dialog.models)

    # Keep the submitted values in the form: a re-render would otherwise reset
    # the model and key inputs the browser is holding.
    attrs = connection_params(params, dialog.connection)

    form =
      dialog.connection
      |> then(&Connection.changeset(&1 || %Connection{}, attrs))
      |> Map.put(:errors, [])
      |> to_form(as: :connection)

    %{
      dialog
      | test: test,
        models: models,
        tested_for: tested_for,
        provider: provider,
        form: form,
        pending_key: pending_key(params, dialog, key)
    }
  end

  # The key is write-only, so a test round trip forces the input to re-render
  # empty. Remembering it server-side lets the following save use it without
  # asking the user to retype it; it is never rendered back.
  defp pending_key(params, dialog, key) do
    case params["api_key"] do
      typed when is_binary(typed) -> if blank?(typed), do: dialog.pending_key, else: key
      _other -> dialog.pending_key
    end
  end

  defp save_connection(socket, dialog, params) do
    attrs =
      params
      |> connection_params(dialog.connection)
      |> maybe_put_pending_key(dialog)

    provider = attrs["provider"] || dialog.provider

    models =
      if tested_same_endpoint?(dialog, attrs) do
        dialog.models
      end

    result =
      case dialog.connection do
        nil ->
          Connections.create(socket.assigns.current_scope.user, attrs, models: models)

        connection ->
          Connections.update(connection, attrs, models: models)
      end

    case result do
      {:ok, _connection} ->
        socket
        |> assign(:connection_dialog, nil)
        |> refresh_connections()
        |> put_flash(:info, "Connection saved.")

      {:error, :limit} ->
        put_flash(
          socket,
          :error,
          "You can keep up to #{Connections.max_per_user()} connections."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, :connection_dialog, %{
          dialog
          | provider: provider,
            models:
              if(provider == dialog.provider,
                do: dialog.models,
                else: ModelCatalog.suggestions(provider)
              ),
            form: to_form(changeset, as: :connection, action: :insert)
        })
    end
  end

  defp run_connection_test(provider, key, base_url, current_models) do
    cond do
      provider not in Connection.provider_ids() ->
        {%{status: :error, message: "Choose a provider first."}, current_models, nil}

      Connection.needs_key?(provider) and blank?(key) ->
        {%{status: :error, message: "Enter an API key to test."}, current_models, nil}

      true ->
        case ModelCatalog.fetch(provider, key, base_url) do
          {:ok, models} ->
            message = "Connected — #{length(models)} models available."

            {%{status: :ok, message: message}, models, %{provider: provider, base_url: base_url}}

          {:error, message} ->
            {%{status: :error, message: message}, current_models, nil}
        end
    end
  end

  # A blank key on an existing connection means "keep the saved one". Dropping
  # the param (rather than writing nil) keeps the changeset from declaring the
  # field required when a key is already stored.
  defp connection_params(params, nil),
    do: Map.take(params, ~w(name provider model_id api_key base_url))

  defp connection_params(params, %Connection{}) do
    attrs = Map.take(params, ~w(name provider model_id api_key base_url))

    if blank?(attrs["api_key"]), do: Map.delete(attrs, "api_key"), else: attrs
  end

  defp maybe_put_pending_key(attrs, %{pending_key: key}) when is_binary(key) do
    if blank?(attrs["api_key"]), do: Map.put(attrs, "api_key", key), else: attrs
  end

  defp maybe_put_pending_key(attrs, _dialog), do: attrs

  defp test_key(params, connection) do
    typed =
      case params["api_key"] do
        key when is_binary(key) -> String.trim(key)
        _other -> ""
      end

    cond do
      typed != "" -> typed
      match?(%Connection{}, connection) -> connection.api_key
      true -> nil
    end
  end

  defp test_base_url(params), do: normalize_url(params["base_url"])

  defp normalize_url(nil), do: nil

  defp normalize_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      trimmed -> String.trim_trailing(trimmed, "/")
    end
  end

  defp normalize_url(_url), do: nil

  defp blank?(value), do: value in [nil, ""]

  defp tested_same_endpoint?(%{tested_for: %{provider: provider, base_url: base_url}}, attrs) do
    attrs["provider"] == provider and normalize_url(attrs["base_url"]) == base_url
  end

  defp tested_same_endpoint?(_dialog, _attrs), do: false

  defp provider_of(dialog), do: dialog.provider

  defp model_placeholder(dialog) do
    case Connection.provider_meta(provider_of(dialog)) do
      %{model_placeholder: placeholder} -> placeholder
      nil -> ""
    end
  end

  defp base_url_placeholder(dialog) do
    Connection.default_base_url(provider_of(dialog)) || "https://…"
  end

  defp key_placeholder(dialog) do
    if dialog.connection && dialog.connection.key_hint do
      "•••••••• (saved)"
    else
      case Connection.provider_meta(provider_of(dialog)) do
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

        Connection.needs_key?(provider_of(dialog)) ->
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

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :success, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:connections, Connections.summaries(user.id))
      |> assign(:providers, Connection.providers())
      |> assign(:connection_dialog, nil)
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("new_connection", _params, socket) do
    {:noreply, assign(socket, :connection_dialog, connection_dialog_state(nil))}
  end

  def handle_event("edit_connection", %{"connection" => id}, socket) do
    case Connections.get(id, socket.assigns.current_scope.user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That connection is no longer available.")}

      connection ->
        {:noreply, assign(socket, :connection_dialog, connection_dialog_state(connection))}
    end
  end

  def handle_event("close_connection_dialog", _params, socket) do
    {:noreply, assign(socket, :connection_dialog, nil)}
  end

  def handle_event("select_provider", params, socket) do
    case socket.assigns.connection_dialog do
      nil ->
        {:noreply, socket}

      dialog ->
        provider = get_in(params, ["connection", "provider"]) || params["provider"]

        models =
          if provider == dialog.provider,
            do: dialog.models,
            else: ModelCatalog.suggestions(provider)

        {:noreply,
         assign(socket, :connection_dialog, %{
           dialog
           | provider: provider,
             models: models,
             test: nil,
             tested_for: nil,
             pending_key: nil
         })}
    end
  end

  def handle_event("save_connection", %{"connection" => params} = payload, socket) do
    case socket.assigns.connection_dialog do
      nil ->
        {:noreply, socket}

      dialog ->
        if payload["action"] == "test" do
          {:noreply, assign(socket, :connection_dialog, test_connection(dialog, params))}
        else
          {:noreply, save_connection(socket, dialog, params)}
        end
    end
  end

  def handle_event("set_default_connection", %{"connection" => id}, socket) do
    user = socket.assigns.current_scope.user

    with %Connection{} = connection <- Connections.get(id, user.id),
         {:ok, _user} <- Connections.set_default(user, connection) do
      {:noreply,
       socket
       |> refresh_connections()
       |> put_flash(:info, "#{connection.name} is now the default.")}
    else
      _other ->
        {:noreply, put_flash(socket, :error, "That connection is no longer available.")}
    end
  end

  def handle_event("delete_connection", %{"connection" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Connections.get(id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That connection is no longer available.")}

      connection ->
        Connections.delete(connection)

        {:noreply,
         socket
         |> assign(:connection_dialog, nil)
         |> refresh_connections()
         |> put_flash(:info, "Connection deleted.")}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
