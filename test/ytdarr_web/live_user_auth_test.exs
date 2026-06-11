defmodule YtdarrWeb.LiveUserAuthTest do
  use YtdarrWeb.ConnCase, async: true

  alias Phoenix.LiveView.Socket
  alias YtdarrWeb.LiveUserAuth

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns),
      endpoint: YtdarrWeb.Endpoint,
      router: YtdarrWeb.Router
    }
  end

  describe ":live_user_optional" do
    test "assigns current_user: nil when no user is in the socket" do
      assert {:cont, %Socket{} = result} =
               LiveUserAuth.on_mount(:live_user_optional, %{}, %{}, socket())

      assert is_nil(result.assigns.current_user)
    end

    test "leaves the existing current_user assign in place" do
      user = user_fixture()
      assert {:cont, %Socket{} = result} =
               LiveUserAuth.on_mount(:live_user_optional, %{}, %{}, socket(%{current_user: user}))

      assert result.assigns.current_user.id == user.id
    end
  end

  describe ":live_user_required" do
    test "continues when a current_user is present" do
      user = user_fixture()
      assert {:cont, %Socket{} = result} =
               LiveUserAuth.on_mount(:live_user_required, %{}, %{}, socket(%{current_user: user}))

      assert result.assigns.current_user.id == user.id
    end

    test "halts and redirects to /sign-in when no user is present" do
      assert {:halt, %Socket{redirected: redirected}} =
               LiveUserAuth.on_mount(:live_user_required, %{}, %{}, socket())

      assert {:redirect, %{to: "/sign-in"}} = redirected
    end
  end

  describe ":live_no_user" do
    test "continues and assigns current_user: nil when no user is present" do
      assert {:cont, %Socket{} = result} =
               LiveUserAuth.on_mount(:live_no_user, %{}, %{}, socket())

      assert is_nil(result.assigns.current_user)
    end

    test "halts and redirects to / when a user is present" do
      user = user_fixture()
      assert {:halt, %Socket{redirected: redirected}} =
               LiveUserAuth.on_mount(:live_no_user, %{}, %{}, socket(%{current_user: user}))

      assert {:redirect, %{to: "/"}} = redirected
    end
  end
end
