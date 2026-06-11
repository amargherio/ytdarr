defmodule Ytdarr.AccountsFixtures do
  @moduledoc """
  Test fixtures for the Accounts domain.
  """

  alias Ytdarr.Accounts.User

  @default_password "password1234"

  @doc """
  Register a user with the password strategy and return the persisted record.

  The returned struct has `__metadata__.token` set so it can be passed directly
  to `AshAuthentication.Plug.Helpers.store_in_session/2`.
  """
  def user_fixture(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])
    password = attrs[:password] || @default_password

    params = %{
      email: attrs[:email] || "user#{unique_id}@example.test",
      password: password,
      password_confirmation: password
    }

    User
    |> Ash.Changeset.for_create(:register_with_password, params)
    |> Ash.create!(authorize?: false)
  end

  @doc "Default password used by `user_fixture/1` when none is supplied."
  def valid_user_password, do: @default_password
end
