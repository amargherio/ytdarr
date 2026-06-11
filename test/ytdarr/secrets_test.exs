defmodule Ytdarr.SecretsTest do
  use ExUnit.Case, async: true

  alias Ytdarr.Secrets

  describe "secret_for/4 for token signing" do
    test "returns the configured token signing secret for the User resource" do
      assert {:ok, secret} =
               Secrets.secret_for(
                 [:authentication, :tokens, :signing_secret],
                 Ytdarr.Accounts.User,
                 [],
                 %{}
               )

      assert is_binary(secret)
      assert byte_size(secret) > 0
    end
  end
end
