defmodule Psc.DocumentsFixtures do
  @moduledoc """
  Test helpers for creating documents via the `Psc.Documents` context.
  """

  alias Psc.AccountsFixtures
  alias Psc.Documents
  alias Psc.Repo

  @doc """
  Returns a map of valid document attributes, with a unique title.
  """
  def valid_document_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: "Document #{System.unique_integer([:positive])}"
    })
  end

  @doc """
  Creates a document owned by a new user (or the one given as `:user`).

  Returns the document struct. The owning `user` is not preloaded — use
  `document_with_user_fixture/1` when the test needs `can_access_document?/2`.
  """
  def document_fixture(attrs \\ %{}) do
    {user, attrs} =
      case Map.pop(attrs, :user) do
        {nil, attrs} -> {AccountsFixtures.user_fixture(), attrs}
        {user, attrs} -> {user, attrs}
      end

    {:ok, document} = Documents.create_document(user.id, valid_document_attributes(attrs))
    document
  end

  @doc """
  Creates a document with its `:user` association preloaded.
  """
  def document_with_user_fixture(attrs \\ %{}) do
    attrs
    |> document_fixture()
    |> Repo.preload(:user)
  end
end
