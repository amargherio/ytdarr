defmodule Ytdarr.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Ytdarr.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:ytdarr, :token_signing_secret)
  end
end
