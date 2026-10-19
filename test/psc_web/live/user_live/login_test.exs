defmodule PscWeb.UserLive.LoginTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Psc.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Register"
      assert html =~ ~s(id="login_form_password")

      # Documents/Canvases/Templates are private: never advertised to guests.
      refute has_element?(lv, ~s|nav a[href="/documents"]|)
      refute has_element?(lv, ~s|nav a[href="/canvas"]|)
      refute has_element?(lv, ~s|nav a[href="/templates"]|)
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "renders inline errors and skips the request when credentials are blank", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      html =
        lv
        |> form("#login_form_password", user: %{email: "", password: ""})
        |> render_submit()

      # Nothing is posted: the form would otherwise land in the controller and
      # show the generic flash instead of pointing at the empty fields.
      refute html =~ "phx-trigger-action"

      assert has_element?(lv, "#login_form_password_email-error", "can't be blank")
      assert has_element?(lv, "#login_form_password_password-error", "can't be blank")

      assert has_element?(lv, ~s|input#login_form_password_email[aria-invalid="true"]|)

      assert has_element?(
               lv,
               ~s|input#login_form_password_email[aria-describedby="login_form_password_email-error"]|
             )
    end

    test "flags a malformed email inline", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> form("#login_form_password", user: %{email: "not-an-email", password: "secret"})
      |> render_submit()

      assert has_element?(
               lv,
               "#login_form_password_email-error",
               "must have the @ sign and no spaces"
             )

      refute has_element?(lv, "#login_form_password_password-error p")
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Sign up button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("#sign_up_link")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      refute html =~ ~s(id="sign_up_link")

      # The password form's email is prefilled and readonly for re-auth
      assert html =~ ~s(id="login_form_password_email")
      assert html =~ ~s(value="#{user.email}")
    end
  end
end
