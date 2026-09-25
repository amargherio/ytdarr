defmodule Ytdarr.Imports.SafeMessageTest do
  use ExUnit.Case, async: true

  alias Ytdarr.Imports.SafeMessage

  test "import errors never disclose filesystem paths or raw causes" do
    private_path = "/srv/private/credentials.txt"

    for reason <- [
          {:outside_import_roots, private_path},
          {:no_import_roots, private_path},
          {:source_unavailable, private_path},
          {:error, {:unexpected, private_path}}
        ] do
      message = SafeMessage.for(reason)
      refute String.contains?(message, private_path)
      refute String.contains?(message, "{:error,")
    end
  end
end
