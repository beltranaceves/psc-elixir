defmodule PscWeb.UserLive.Settings do
  use PscWeb, :live_view

  on_mount {PscWeb.UserAuth, :require_sudo_mode}

  # SaladUI button/input/form called qualified (UIButton/UIInput/UIForm):
  # CoreComponents is global via html_helpers and defines the same names.
  alias Psc.Agent.Connection
  alias Psc.Agent.Connections
  alias Psc.Agent.ModelCatalog
  alias PscWeb.UserLive.SettingsAgentConnections
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

      <SettingsAgentConnections.connections connections={@connections} />

      <SettingsAgentConnections.dialog dialog={@connection_dialog} providers={@providers} />
    </Layouts.app>
    """
  end

  ## Agent connections

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
    {:noreply, assign(socket, :connection_dialog, SettingsAgentConnections.dialog_state(nil))}
  end

  def handle_event("edit_connection", %{"connection" => id}, socket) do
    case Connections.get(id, socket.assigns.current_scope.user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That connection is no longer available.")}

      connection ->
        {:noreply,
         assign(socket, :connection_dialog, SettingsAgentConnections.dialog_state(connection))}
    end
  end

  def handle_event("close_connection_dialog", _params, socket) do
    {:noreply, assign(socket, :connection_dialog, nil)}
  end

  def handle_event("toggle_provider_list", _params, socket) do
    case socket.assigns.connection_dialog do
      nil ->
        {:noreply, socket}

      dialog ->
        {:noreply,
         assign(socket, :connection_dialog, %{dialog | provider_open: not dialog.provider_open})}
    end
  end

  def handle_event("close_provider_list", _params, socket) do
    case socket.assigns.connection_dialog do
      nil ->
        {:noreply, socket}

      dialog ->
        {:noreply, assign(socket, :connection_dialog, %{dialog | provider_open: false})}
    end
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
             provider_open: false,
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
