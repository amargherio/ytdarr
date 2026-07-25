defmodule Ytdarr.Imports.SafeMessage do
  @moduledoc false

  @fallback "Ytdarr could not import this file. Check the server logs and try again."

  @spec for(term()) :: String.t()
  def for(reason) do
    message =
      cond do
        contains?(reason, :ffprobe_unavailable) ->
          "ffprobe is unavailable. Install ffmpeg and restart Ytdarr."

        contains?(reason, :ffprobe_timeout) ->
          "Video inspection timed out."

        contains?(reason, :no_video_stream) ->
          "The selected file does not contain a video stream."

        contains?(reason, :source_missing) or contains?(reason, :source_unavailable) or
            contains?(reason, :enoent) ->
          "The selected file is no longer available."

        contains?(reason, :source_changed) ->
          "The selected file changed. Select it again."

        contains?(reason, :destination_changed) or contains?(reason, :missing_upload_date) ->
          "The video's metadata changed. Reopen Import and try again."

        contains?(reason, :destination_exists) ->
          "The canonical destination already exists. Remove it before importing."

        contains?(reason, :eacces) or contains?(reason, :eperm) or
          contains?(reason, :source_not_writable) or contains?(reason, :source_unreadable) or
            contains?(reason, :permission_denied) ->
          "Ytdarr cannot read and move the selected file. Check its permissions."

        contains?(reason, :import_conflict) ->
          "An import is already in progress for this video."

        true ->
          @fallback
      end

    String.slice(message, 0, 500)
  end

  defp contains?(value, expected) when value == expected, do: true

  defp contains?(value, expected) when is_list(value),
    do: Enum.any?(value, &contains?(&1, expected))

  defp contains?(value, expected) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.any?(&contains?(&1, expected))
  end

  defp contains?(value, expected) when is_map(value) do
    Enum.any?(value, fn {key, nested} ->
      contains?(key, expected) or contains?(nested, expected)
    end)
  end

  defp contains?(_value, _expected), do: false
end
