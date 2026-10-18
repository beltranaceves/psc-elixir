defmodule PscWeb.Components.UI.Form do
  @moduledoc """
  Form-related components that help build accessible forms.

  SaladUI doesn't define its own form component, but instead provides a set of
  form-related components to enhance the native Phoenix LiveView form.

  ## Examples:

      <.form
        class="space-y-6"
        for={@form}
        id="project-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.form_item>
          <.form_label>What is your project's name?</.form_label>
          <.form_control>
            <.input field={@form[:name]} type="text" phx-debounce="500" />
          </.form_control>
          <.form_description>
            This is your public display name.
          </.form_description>
          <.form_message field={@form[:name]} />
        </.form_item>

        <div class="w-full flex flex-row-reverse">
          <.button
            class="btn btn-secondary btn-md"
            icon="inbox_arrow_down"
            phx-disable-with="Saving..."
          >
            Save project
          </.button>
        </div>
      </.form>
  """
  use PscWeb.Components.UI, :component

  import PscWeb.Components.UI.Icon

  alias Phoenix.HTML.FormField

  @doc """
  Form item component that acts as a container for a form field.

  ## Examples:

      <.form_item>
        <.form_label>Email</.form_label>
        <.form_control>
          <.input field={@form[:email]} type="email" />
        </.form_control>
        <.form_message field={@form[:email]} />
      </.form_item>
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global

  def form_item(assigns) do
    ~H"""
    <div class={classes(["space-y-2", @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Form label component that renders a label for a form field.

  Shows validation errors through text color when a field has errors.

  ## Examples:

      <.form_label>Email</.form_label>
      <.form_label field={@form[:email]}>Email</.form_label>
  """
  attr :class, :string, default: nil

  attr :field, FormField,
    default: nil,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :for, :string, default: nil

  attr :error, :boolean, default: false, doc: "whether the field has an error"
  slot :inner_block, required: true
  attr :rest, :global

  def form_label(assigns) do
    assigns = assign(assigns, error: assigns[:error] || has_error?(assigns[:field]))

    ~H"""
    <PscWeb.Components.UI.Label.label
      for={(@field && @field.id) || @for}
      class={
        classes([
          @error && "text-destructive",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </PscWeb.Components.UI.Label.label>
    """
  end

  @doc """
  Form control component that wraps input elements.

  This is a simple pass-through component that renders its inner block.

  ## Examples:

      <.form_control>
        <.input field={@form[:email]} type="email" />
      </.form_control>
  """
  slot :inner_block, required: true

  def form_control(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    """
  end

  @doc """
  Form description component that provides additional context for a form field.

  ## Examples:

      <.form_description>
        We'll only use your email for account-related purposes.
      </.form_description>
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global

  def form_description(assigns) do
    ~H"""
    <p class={classes(["text-muted-foreground text-sm", @class])} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Form message component that displays validation errors for a form field.

  ## Examples:

      <.form_message field={@form[:email]} />

      <.form_message>
        Please enter a valid email address.
      </.form_message>
  """
  attr :field, FormField,
    default: nil,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :any,
    default: [],
    doc: "a list of error messages to display"

  attr :class, :string, default: nil
  slot :inner_block, required: false
  attr :rest, :global

  def form_message(assigns) do
    errors =
      case assigns[:errors] do
        [] -> field_errors(assigns[:field])
        errors -> errors
      end

    # A custom inner-block message takes precedence over changeset errors.
    has_custom_message = assigns[:inner_block] not in [nil, []]
    errors = if has_custom_message, do: [], else: errors

    assigns =
      assigns
      |> assign(:errors, errors)
      |> assign(:has_custom_message, has_custom_message)
      |> assign(:error_id, error_id(assigns[:field]))

    ~H"""
    <div
      :if={@error_id || @has_custom_message}
      id={@error_id}
      aria-live="polite"
      class={classes(["space-y-1", @class])}
      {@rest}
    >
      <p
        :if={@has_custom_message}
        class="flex items-start gap-1.5 rounded-md border border-destructive/25 px-2.5 py-1.5 text-sm font-medium text-destructive"
      >
        <.icon name="hero-exclamation-circle" class="mt-0.5 size-4 shrink-0" />
        <span>{render_slot(@inner_block)}</span>
      </p>
      <p
        :for={message <- @errors}
        class="flex items-start gap-1.5 rounded-md border border-destructive/25 px-2.5 py-1.5 text-sm font-medium text-destructive"
      >
        <.icon name="hero-exclamation-circle" class="mt-0.5 size-4 shrink-0" />
        <span>{message}</span>
      </p>
    </div>
    """
  end

  defp error_id(%FormField{id: id}) when is_binary(id), do: "#{id}-error"
  defp error_id(_), do: nil
end
