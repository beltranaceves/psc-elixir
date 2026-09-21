defmodule Psc.DocumentsTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Documents
  alias Psc.Documents.CRDT
  alias Psc.DocumentsFixtures

  describe "create_document/2" do
    test "creates a document for the given user" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, document} = Documents.create_document(user.id, %{title: "My doc"})
      assert document.title == "My doc"
      assert document.user_id == user.id
    end

    test "applies the schema defaults" do
      user = AccountsFixtures.user_fixture()
      {:ok, document} = Documents.create_document(user.id, %{title: "My doc"})

      assert document.snapshot_seq == 0
      assert document.snapshot_content == ""
      assert document.shared_with == []
    end

    test "returns an error changeset when the title is missing" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} = Documents.create_document(user.id, %{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_user_documents/1" do
    test "returns only documents owned by that user" do
      user = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()

      mine = DocumentsFixtures.document_fixture(%{user: user})
      _theirs = DocumentsFixtures.document_fixture(%{user: other})

      assert [document] = Documents.list_user_documents(user.id)
      assert document.id == mine.id
    end

    test "returns an empty list when the user has no documents" do
      user = AccountsFixtures.user_fixture()

      assert Documents.list_user_documents(user.id) == []
    end
  end

  describe "list_shared_documents/1" do
    test "returns documents whose shared_with list contains the email" do
      owner = AccountsFixtures.user_fixture()
      document = DocumentsFixtures.document_fixture(%{user: owner})

      {:ok, _} = Documents.share_document_with(document, "collaborator@example.com")

      assert [shared] = Documents.list_shared_documents("collaborator@example.com")
      assert shared.id == document.id
    end

    test "returns an empty list when nothing is shared with the email" do
      AccountsFixtures.user_fixture()
      _ = DocumentsFixtures.document_fixture()

      assert Documents.list_shared_documents("nobody@example.com") == []
    end
  end

  describe "get_document/1" do
    test "returns the document" do
      document = DocumentsFixtures.document_fixture()

      assert Documents.get_document(document.id).id == document.id
    end

    test "returns nil for an unknown id" do
      assert Documents.get_document(-1) == nil
    end
  end

  describe "update_document_title/2" do
    test "updates the title" do
      document = DocumentsFixtures.document_fixture()

      assert {:ok, updated} = Documents.update_document_title(document, "Renamed")
      assert updated.title == "Renamed"
    end
  end

  describe "sharing" do
    test "share_document_with/2 adds the email" do
      document = DocumentsFixtures.document_fixture()

      assert {:ok, updated} = Documents.share_document_with(document, "a@example.com")
      assert updated.shared_with == ["a@example.com"]
    end

    test "share_document_with/2 does not duplicate an existing email" do
      document = DocumentsFixtures.document_fixture()

      {:ok, once} = Documents.share_document_with(document, "a@example.com")
      {:ok, twice} = Documents.share_document_with(once, "a@example.com")

      assert twice.shared_with == ["a@example.com"]
    end

    test "unshare_document/2 removes the email" do
      document = DocumentsFixtures.document_fixture()

      {:ok, shared} = Documents.share_document_with(document, "a@example.com")
      assert {:ok, unshared} = Documents.unshare_document(shared, "a@example.com")

      assert unshared.shared_with == []
    end

    test "can_access_document?/2 allows the owner" do
      document = DocumentsFixtures.document_with_user_fixture()

      assert Documents.can_access_document?(document, document.user.email)
    end

    test "can_access_document?/2 allows a shared email" do
      document = DocumentsFixtures.document_with_user_fixture()
      {:ok, shared} = Documents.share_document_with(document, "collaborator@example.com")

      assert Documents.can_access_document?(shared, "collaborator@example.com")
    end

    test "can_access_document?/2 denies an unrelated email" do
      document = DocumentsFixtures.document_with_user_fixture()

      refute Documents.can_access_document?(document, "stranger@example.com")
    end
  end

  describe "apply_operation/3" do
    test "persists the operation and returns the sequence number" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      assert {:ok, 1} =
               Documents.apply_operation(
                 document.id,
                 user.id,
                 %{"type" => "insert", "pos" => 0, "char" => "H"}
               )
    end

    test "sequence numbers increase with each operation" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, first} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 0, "char" => "a"}
        )

      {:ok, second} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 1, "char" => "b"}
        )

      assert second == first + 1
    end

    test "operations can be replayed to rebuild the text" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      for {char, pos} <- [{"H", 0}, {"i", 1}] do
        {:ok, _} =
          Documents.apply_operation(
            document.id,
            user.id,
            %{"type" => "insert", "pos" => pos, "char" => char}
          )
      end

      assert CRDT.rebuild_text(document.id) == "Hi"
    end

    test "publishes the operation on the document topic" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      Phoenix.PubSub.subscribe(Psc.PubSub, Documents.pubsub_topic(document.id))

      operation = %{"type" => "insert", "pos" => 0, "char" => "X"}
      {:ok, seq} = Documents.apply_operation(document.id, user.id, operation)

      assert_receive {:operation, user_id, ^operation, ^seq}
      assert user_id == user.id
    end
  end

  describe "content persistence" do
    test "get_document_content/1 replays stored events" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, _} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 0, "char" => "H"}
        )

      assert Documents.get_document_content(document.id) == "H"
    end

    test "save_content_to_db/2 stores content and the snapshot sequence" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, 1} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 0, "char" => "H"}
        )

      assert {:ok, saved} = Documents.save_content_to_db(document.id, "H")
      assert saved.content == "H"
      assert saved.snapshot_seq == 1
    end

    test "saved content is not double-applied when events are replayed" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, _} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 0, "char" => "H"}
        )

      # Persist the text built from the event, recording snapshot_seq = 1
      {:ok, _} = Documents.save_content_to_db(document.id, "H")

      # The event at seq 1 is now covered by the saved content and must not be replayed
      assert Documents.get_document_content(document.id) == "H"
    end

    test "events recorded after a save are replayed on top of the saved content" do
      document = DocumentsFixtures.document_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, _} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 0, "char" => "H"}
        )

      {:ok, _} = Documents.save_content_to_db(document.id, "H")

      # A later event (seq 2) is above snapshot_seq and must be replayed
      {:ok, _} =
        Documents.apply_operation(
          document.id,
          user.id,
          %{"type" => "insert", "pos" => 1, "char" => "i"}
        )

      assert Documents.get_document_content(document.id) == "Hi"
    end
  end

  describe "get_document_with_events/1" do
    test "preloads the event log in sequence order" do
      document = DocumentsFixtures.document_fixture()

      assert Documents.get_document_with_events(document.id).events == []
    end
  end

  describe "pubsub_topic/1" do
    test "namespaces the topic by document id" do
      assert Documents.pubsub_topic(42) == "document:42"
    end
  end
end