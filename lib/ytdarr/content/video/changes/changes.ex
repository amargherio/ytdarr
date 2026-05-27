defmodule Ytdarr.Content.Video.Changes do
  @moduledoc "Helper functions for Video changes"

  def utc_now_truncated do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
