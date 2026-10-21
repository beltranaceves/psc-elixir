defmodule Psc.AccountsAdminTest do
  # `System.put_env/2` is global, so this module cannot run concurrently with
  # anything else that reads ADMIN_EMAILS.
  use Psc.DataCase, async: false

  import Ecto.Changeset, only: [get_change: 2]

  alias Psc.Accounts
  alias Psc.Accounts.User
  alias Psc.AccountsFixtures

  describe "roles" do
    test "new users are members" do
      assert AccountsFixtures.user_fixture().role == :member
    end

    test "registration params cannot grant the role" do
      changeset =
        User.registration_changeset(%User{}, %{
          "email" => "someone@example.com",
          "password" => "a long enough password",
          "role" => "admin"
        })

      assert is_nil(get_change(changeset, :role))
    end

    test "promote and demote go through the context" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, admin} = Accounts.promote_admin(user)
      assert admin.role == :admin
      assert Accounts.admin?(admin)

      # The last-admin rule needs a second admin before the demotion is legal.
      _second = AccountsFixtures.admin_fixture()

      assert {:ok, member} = Accounts.demote_admin(admin)
      assert member.role == :member
      refute Accounts.admin?(member)
    end

    test "the last admin cannot be demoted" do
      admin = AccountsFixtures.admin_fixture()

      assert Accounts.admin_count() == 1
      assert {:error, :last_admin} = Accounts.demote_admin(admin)
      assert Accounts.get_user!(admin.id).role == :admin
    end

    test "an admin can be demoted when another remains" do
      first = AccountsFixtures.admin_fixture()
      _second = AccountsFixtures.admin_fixture()

      assert {:ok, member} = Accounts.demote_admin(first)
      assert member.role == :member
      assert Accounts.admin_count() == 1
    end
  end

  describe "bootstrap_admins/0" do
    setup do
      on_exit(fn ->
        if value = Process.get(:previous_admin_emails),
          do: System.put_env("ADMIN_EMAILS", value),
          else: System.delete_env("ADMIN_EMAILS")

        if value = Process.get(:previous_admin_password),
          do: System.put_env("ADMIN_PASSWORD", value),
          else: System.delete_env("ADMIN_PASSWORD")
      end)

      Process.put(:previous_admin_emails, System.get_env("ADMIN_EMAILS"))
      Process.put(:previous_admin_password, System.get_env("ADMIN_PASSWORD"))

      System.delete_env("ADMIN_EMAILS")
      System.delete_env("ADMIN_PASSWORD")
      :ok
    end

    test "promotes an existing account" do
      user = AccountsFixtures.user_fixture()
      System.put_env("ADMIN_EMAILS", user.email)

      assert {1, 0, []} = Accounts.bootstrap_admins()
      assert Accounts.get_user!(user.id).role == :admin
    end

    test "creates a missing account when a password is configured" do
      System.put_env("ADMIN_EMAILS", "root@example.com")
      System.put_env("ADMIN_PASSWORD", "a very long bootstrap password")

      assert {0, 1, []} = Accounts.bootstrap_admins()

      admin = Accounts.get_user_by_email("root@example.com")
      assert admin.role == :admin
      assert admin.confirmed_at
      assert User.valid_password?(admin, "a very long bootstrap password")
    end

    test "skips a missing account when no password is configured" do
      System.put_env("ADMIN_EMAILS", "root@example.com")

      assert {0, 0, ["root@example.com"]} = Accounts.bootstrap_admins()
      assert is_nil(Accounts.get_user_by_email("root@example.com"))
    end

    test "is idempotent" do
      System.put_env("ADMIN_EMAILS", "root@example.com")
      System.put_env("ADMIN_PASSWORD", "a very long bootstrap password")

      assert {0, 1, []} = Accounts.bootstrap_admins()
      assert {0, 0, []} = Accounts.bootstrap_admins()
      assert Accounts.admin_count() == 1
    end

    test "handles a list of addresses" do
      one = AccountsFixtures.user_fixture()
      System.put_env("ADMIN_EMAILS", " #{one.email}, second@example.com ;")
      System.put_env("ADMIN_PASSWORD", "a very long bootstrap password")

      assert {1, 1, []} = Accounts.bootstrap_admins()
      assert Accounts.get_user!(one.id).role == :admin
      assert Accounts.get_user_by_email("second@example.com").role == :admin
    end
  end
end
