defmodule Ytdarr.Accounts do
  use Ash.Domain, otp_app: :ytdarr, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Ytdarr.Accounts.Token
    resource Ytdarr.Accounts.User
  end
end
