defmodule PscWeb.UserLive.Settings do
  use PscWeb, :live_view

  on_mount {PscWeb.UserAuth, :require_sudo_mode}

  # SaladUI button/input/form called qualified (UIButton/UIInput/UIForm):
  # CoreComponents is global via html_helpers and defines the same names.
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

      <div class="mt-6 rounded-xl border border-base-content/10 bg-base-200 p-6">
        <h3 class="text-lg font-medium text-base-content">Agent</h3>
        <p class="mt-1 text-sm text-base-content/60">
          The canvas agent calls a language model you choose, with a key of your own.
          The key is stored for your account only and never shown again after you save it.
        </p>

        <p :if={@agent_key?} class="mt-3 text-sm text-success">
          A key is saved{@agent_model_label}. Saving a new one replaces it.
        </p>

        <.form for={@agent_key_form} id="agent-key-form" phx-submit="save_agent_key" class="mt-4">
          <UIForm.form_item>
            <UIForm.form_label field={@agent_key_form[:provider]}>Provider</UIForm.form_label>
            <UIForm.form_control>
              <select
                name="user[provider]"
                id="agent-provider"
                class="w-full rounded-lg border border-base-content/20 bg-base-100 px-3 py-2 text-sm"
              >
                <option
                  :for={provider <- @agent_providers}
                  value={provider}
                  selected={provider == @agent_provider}
                >
                  {provider}
                </option>
              </select>
            </UIForm.form_control>
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@agent_key_form[:model_id]}>Model</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                name="user[model_id]"
                id="agent-model-id"
                value={@agent_model_id}
                autocomplete="off"
                spellcheck="false"
                placeholder={@agent_default_model}
              />
            </UIForm.form_control>
            <p class="mt-1 text-xs text-base-content/50">
              Leave blank to use this instance's default ({@agent_default_model}).
            </p>
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@agent_key_form[:agent_api_key]}>
              API key
            </UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@agent_key_form[:agent_api_key]}
                type="password"
                autocomplete="off"
                spellcheck="false"
                placeholder={if @agent_key?, do: "•••••••• (saved)", else: "sk-…"}
              />
            </UIForm.form_control>
            <UIForm.form_message field={@agent_key_form[:agent_api_key]} />
          </UIForm.form_item>

          <UIButton.button phx-disable-with="Saving..." class="w-full mt-3">
            Save agent settings
          </UIButton.button>
        </.form>

        <button
          :if={@agent_key?}
          type="button"
          phx-click="clear_agent_key"
          data-confirm="Remove your saved API key?"
          class="mt-3 w-full rounded-lg border border-error/40 px-3 py-1.5 text-sm text-error hover:bg-error/10"
        >
          Remove saved key
        </button>
      </div>
    </Layouts.app>
    """
  end

  # A blank key field means "keep the saved one": only an explicit removal
  # clears it, so editing the model cannot silently wipe the credential.
  defp maybe_put_key(attrs, key) when is_binary(key) do
    if String.trim(key) == "", do: attrs, else: Map.put(attrs, "agent_api_key", key)
  end

  defp maybe_put_key(attrs, _key), do: attrs

  defp build_agent_model(%{"provider" => provider, "model_id" => model_id}) do
    model_id = String.trim(to_string(model_id || ""))

    if provider in Psc.Accounts.User.agent_providers() and model_id != "" do
      "#{provider}:#{model_id}"
    end
  end

  defp build_agent_model(_params), do: nil

  defp agent_provider(%{agent_model: nil}), do: "openai"

  defp agent_provider(%{agent_model: model}) do
    model |> String.split(":", parts: 2) |> hd()
  end

  defp agent_model_id(%{agent_model: nil}), do: ""

  defp agent_model_id(%{agent_model: model}) do
    model |> String.split(":", parts: 2) |> List.last()
  end

  defp default_agent_model do
    case Application.get_env(:jido_ai, :model_aliases, %{}) do
      %{default: model} when is_binary(model) -> model
      _other -> "AGENT_MODEL"
    end
  end

  defp agent_model_label(%{agent_model: nil}), do: ""

  defp agent_model_label(%{agent_model: model}), do: " for #{model}"

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
      |> assign(:agent_key_form, to_form(Accounts.change_agent_key(user, %{})))
      |> assign(:agent_key?, Psc.Accounts.User.agent_key?(user))
      |> assign(:agent_providers, Psc.Accounts.User.agent_providers())
      |> assign(:agent_provider, agent_provider(user))
      |> assign(:agent_model_id, agent_model_id(user))
      |> assign(:agent_default_model, default_agent_model())
      |> assign(:agent_model_label, agent_model_label(user))
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

  def handle_event("save_agent_key", params, socket) do
    user_params = params["user"] || %{}
    user = socket.assigns.current_scope.user

    attrs =
      %{"agent_model" => build_agent_model(user_params)}
      |> maybe_put_key(user_params["agent_api_key"])

    case Accounts.update_agent_key(user, attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:agent_key_form, to_form(Accounts.change_agent_key(user, %{})))
         |> assign(:agent_key?, Psc.Accounts.User.agent_key?(user))
         |> assign(:agent_provider, agent_provider(user))
         |> assign(:agent_model_id, agent_model_id(user))
         |> assign(:agent_model_label, agent_model_label(user))
         |> put_flash(:info, "Agent settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :agent_key_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("clear_agent_key", _params, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_agent_key(user, %{"agent_api_key" => ""}) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:agent_key?, false)
         |> assign(:agent_model_label, agent_model_label(user))
         |> put_flash(:info, "Agent API key removed.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not remove the key.")}
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
