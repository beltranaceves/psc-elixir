defmodule PscWeb.Markdown do
  @moduledoc """
  Server-side Markdown rendering shared by editable document and canvas content.
  """

  require Logger

  @default_empty_message "Click to edit"

  @doc """
  Converts Markdown into safe HTML for the rendered-content views.

  Empty content gets an interactive placeholder. Earmark errors are logged and
  displayed as escaped text rather than being injected as HTML.
  """
  def render(markdown, opts \\ [])

  def render(nil, opts), do: render("", opts)

  def render(markdown, opts) when is_binary(markdown) do
    empty_message = Keyword.get(opts, :empty_message, @default_empty_message)

    if String.trim(markdown) == "" do
      empty_html(empty_message)
    else
      case Earmark.as_html(escaped_html(markdown)) do
        {:ok, html, _messages} ->
          unescape_html_entities(html)

        {:error, _html, messages} ->
          Logger.warning("Markdown rendering failed: #{inspect(messages)}")
          escaped_html(markdown)
      end
    end
  end

  defp empty_html(message) do
    ~s(<div class="p-2 rounded text-base-content/40">#{escaped_html(message)}</div>)
  end

  defp escaped_html(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp unescape_html_entities(html) do
    html
    |> String.replace("&amp;lt;", "&lt;")
    |> String.replace("&amp;gt;", "&gt;")
    |> String.replace("&amp;amp;", "&amp;")
    |> String.replace("&amp;quot;", "&quot;")
    |> String.replace("&amp;#39;", "&#39;")
  end
end
