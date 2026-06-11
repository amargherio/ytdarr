defmodule YtdarrWeb.AuthControllerTest do
  use YtdarrWeb.ConnCase, async: false

  alias YtdarrWeb.AuthController

  setup %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()

    %{conn: conn}
  end

  describe "success/4" do
    test "stores user in session, sets flash, and redirects to root by default", %{conn: conn} do
      user = user_fixture()

      conn = AuthController.success(conn, {:password, :sign_in}, user, "token")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You are now signed in"
      assert conn.assigns[:current_user].id == user.id
    end

    test "honors the return_to in session and clears it", %{conn: conn} do
      user = user_fixture()
      conn = Plug.Conn.put_session(conn, :return_to, "/channels")

      conn = AuthController.success(conn, {:password, :sign_in}, user, "token")

      assert redirected_to(conn) == "/channels"
      assert is_nil(Plug.Conn.get_session(conn, :return_to))
    end

    test "uses the confirm-new-user flash for that activity", %{conn: conn} do
      user = user_fixture()

      conn = AuthController.success(conn, {:confirm_new_user, :confirm}, user, "token")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Your email address has now been confirmed"
    end

    test "uses the password-reset flash for that activity", %{conn: conn} do
      user = user_fixture()

      conn = AuthController.success(conn, {:password, :reset}, user, "token")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Your password has successfully been reset"
    end
  end

  describe "failure/3" do
    test "sets the default error flash and redirects to sign-in", %{conn: conn} do
      conn = AuthController.failure(conn, {:password, :sign_in}, :invalid)

      assert redirected_to(conn) == "/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Incorrect email or password"
    end

    test "explains an unconfirmed-account failure", %{conn: conn} do
      reason = %AshAuthentication.Errors.AuthenticationFailed{
        caused_by: %Ash.Error.Forbidden{
          errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
        }
      }

      conn = AuthController.failure(conn, {:password, :sign_in}, reason)

      assert redirected_to(conn) == "/sign-in"
      message = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert message =~ "have not confirmed your account"
    end
  end

  describe "sign_out/2" do
    test "clears session, sets info flash, and redirects to root", %{conn: conn} do
      user = user_fixture()
      conn = sign_in(conn, user)

      conn = AuthController.sign_out(conn, %{})

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You are now signed out"
    end

    test "honors return_to from session when set", %{conn: conn} do
      conn = Plug.Conn.put_session(conn, :return_to, "/sign-in")

      conn = AuthController.sign_out(conn, %{})

      assert redirected_to(conn) == "/sign-in"
    end
  end
end
