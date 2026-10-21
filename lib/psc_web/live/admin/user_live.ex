defmodule PscWeb.Admin.UserLive do
  @moduledoc """
  Administration of user accounts.

  The only writable field is `role`; email and confirmation are read-only, and
  there is no create form — accounts are created by registration or by the
  `ADMIN_EMAILS` bootstrap. The changeset enforces the last-admin rule that
  `Psc.Accounts.demote_admin/1` enforces in the context.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Psc.Accounts.User,
      repo: Psc.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    init_order: %{by: :inserted_at, direction: :desc},
    fluid?: true

  import Ecto.Changeset

  alias Psc.Accounts
  alias Psc.Accounts.User

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def layout(_assigns), do: {PscWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def fields do
    [
      email: %{
        module: Backpex.Fields.Email,
        label: "Email",
        searchable: true,
        orderable: true,
        readonly: true
      },
      role: %{
        module: Backpex.Fields.Select,
        label: "Role",
        options: [Member: :member, Admin: :admin],
        help_text: "The last admin cannot be demoted."
      },
      confirmed_at: %{
        module: Backpex.Fields.DateTime,
        label: "Confirmed",
        readonly: true,
        except: [:new, :edit]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Registered",
        readonly: true,
        except: [:new, :edit]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, action, _item) when action in [:index, :show, :edit], do: admin?(assigns)
  def can?(_assigns, _action, _item), do: false

  @doc """
  The role changeset, plus the last-admin guard.

  Backpex calls this with either the schema struct or an `Ecto.Changeset`
  (while validating a form), so the guard reads the original from
  `changeset.data` rather than pattern-matching the argument.
  """
  def changeset(user_or_changeset, attrs, _metadata) do
    changeset = User.role_changeset(user_or_changeset, attrs)
    original = changeset.data

    if get_change(changeset, :role) == :member and original.role == :admin and
         Accounts.admin_count() <= 1 do
      add_error(changeset, :role, "cannot demote the last admin")
    else
      changeset
    end
  end

  defp admin?(assigns), do: Accounts.admin?(assigns.current_scope.user)
end
