defmodule Ytdarr.Services.YouTube.Parser do
  @moduledoc """
  Functions to parse YouTube API data into Ytdarr content structures.
  """

  alias Ytdarr.Services.YouTube.Models
  alias Ytdarr.Content

  def create_ytdarr_channel(%Models.Channel{} = yt_channel) do
    %Content.Channel{
      external_id: yt_channel.id,
      name: yt_channel.title,
      url: yt_channel.url,
      description: yt_channel.description,
      platform: "YouTube",
      avatar_url: yt_channel.thumbnail_url,
      banner_url: yt_channel.banner_url,
      platform_username: yt_channel.custom_url,
      uploads_playlist_id: yt_channel.uploads_playlist_id,
      is_monitored: false,
      is_monitored_since: nil,
      last_checked_at: nil,
      base_path: nil,
      generic_video_path: nil
    }
  end

  def create_ytdarr_playlist(%Models.Playlist{} = yt_playlist, channel_id) do
    %Content.Playlist{
      external_id: yt_playlist.id,
      name: yt_playlist.title,
      url: yt_playlist.url,
      description: yt_playlist.description,
      video_count: yt_playlist.video_count,
      is_monitored: false,
      last_checked_at: nil,
      channel_id: channel_id
    }
  end

  # ------------------------
  # Shared parsing utilities
  # ------------------------
  @doc """
  Parses an ISO8601 date/time string into a Date (UTC) or returns nil.
  """
  def parse_date(nil), do: nil

  def parse_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> DateTime.to_date(dt)
      _ -> nil
    end
  end

  def parse_date(_), do: nil

  @doc """
  Parses a potentially stringified integer.
  """
  def parse_int(nil), do: nil

  def parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  def parse_int(int) when is_integer(int), do: int
  def parse_int(_), do: nil

  @doc """
  Parses an ISO8601 YouTube duration (e.g., PT1H2M3S) into total seconds. Returns nil on failure.
  """
  def parse_duration(nil), do: nil

  def parse_duration(duration) when is_binary(duration) do
    # Basic regex decomposition; YouTube durations are a subset of ISO8601
    regex = ~r/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/

    case Regex.run(regex, duration) do
      [_, h, m, s] ->
        (parse_int(h) || 0) * 3600 + (parse_int(m) || 0) * 60 + (parse_int(s) || 0)

      [_, h, m] ->
        (parse_int(h) || 0) * 3600 + (parse_int(m) || 0) * 60

      [_, h] ->
        (parse_int(h) || 0) * 3600

      _ ->
        nil
    end
  end

  def parse_duration(_), do: nil
end
