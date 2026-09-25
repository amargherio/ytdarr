defmodule Ytdarr.ImportsTest do
  use Ytdarr.DataCase, async: false

  alias Ytdarr.Imports

  test "uses configured queue options before an importer producer is running" do
    original = Application.fetch_env!(:ytdarr, Oban)
    on_exit(fn -> Application.put_env(:ytdarr, Oban, original) end)

    Application.put_env(
      :ytdarr,
      Oban,
      Keyword.put(original, :queues, video_importer: [limit: 3])
    )

    assert Imports.queue_concurrency() == 3
  end
end
