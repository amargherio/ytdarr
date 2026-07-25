defmodule Ytdarr.ImportsTest do
  use Ytdarr.DataCase, async: true

  alias Ytdarr.Imports

  test "reports the configured two-slot importer queue" do
    assert Imports.queue_concurrency() == 2
  end
end
