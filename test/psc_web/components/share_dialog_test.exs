defmodule PscWeb.Components.ShareDialogTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PscWeb.Components.ShareDialog

  defp render_dialog(open?) do
    render_component(&ShareDialog.share_dialog/1, %{
      id: "share-test",
      open: open?,
      share_event: "share",
      remove_event: "remove"
    })
  end

  test "a closed dialog is hidden in the initial markup" do
    html = render_dialog(false)

    assert html =~ ~r/data-part="content"[^>]*hidden/
    assert html =~ ~r/data-state="closed"/
    refute html =~ ~r/data-part="content"[^>]*data-state="open"/
  end

  test "an open dialog is visible in the initial markup" do
    html = render_dialog(true)

    refute html =~ ~r/data-part="content"[^>]*hidden/
    assert html =~ ~r/data-part="content"[^>]*data-state="open"/
  end
end
