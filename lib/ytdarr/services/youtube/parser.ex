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
      is_monitored: false,
      is_monitored_since: nil,
      last_checked_at: nil,
      base_path: nil,
      generic_video_path: nil
    }
  end

end
