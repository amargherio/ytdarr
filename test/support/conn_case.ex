defmodule YtdarrWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use YtdarrWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint YtdarrWeb.Endpoint

      use YtdarrWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Ytdarr.AccountsFixtures
      import YtdarrWeb.ConnCase
    end
  end

  setup tags do
    Ytdarr.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Initialize the session and store the given user so subsequent requests are
  authenticated as that user.
  """
  def sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  @doc """
  Setup helper that registers a fresh user and signs them in.

      setup :register_and_sign_in_user
  """
  def register_and_sign_in_user(%{conn: conn}) do
    user = Ytdarr.AccountsFixtures.user_fixture()
    %{conn: sign_in(conn, user), user: user}
  end
end
