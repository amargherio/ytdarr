defmodule Ytdarr.Services.YouTube.Client do
  @moduledoc """
  High-level YouTube API client for fetching channel, playlist, and video data.
  """

  alias Ytdarr.Services.YouTube.{API, Parser, Models}
  alias Ytdarr.Content

  def search_channels(query) do
    case API.search_channels(query) do
      {:ok, api_response} ->
        data = Enum.map(api_response.items, &Models.Channel.from_api/1)
        if data == [] do
          {:error, :no_results}
        else
          channels = []
          Enum.each(data, fn item ->
            existing = Content.get_channel_by_external_id(item.id)
            if is_nil(existing) do
              # not already monitored, so create a Ytdarr.Content.Channel struct and
              # add it to the list to return
              channel = Parser.create_ytdarr_channel(item)
              ^channels = [channel | channels]
            else
              # log that this channel is already monitored and skip
              Phoenix.Logger.info("Channel #{item.id} is already monitored, skipping")
            end
          end)
          {:ok, Enum.reverse(channels)}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channel(channel_identifier) do
    case API.get_channel(channel_identifier) do
      {:ok, api_response} ->
        case api_response.items do
          [first | _] ->
            channel = Models.Channel.from_api(first)
            {:ok, Parser.create_ytdarr_channel(channel)}
          [] ->
            {:error, :not_found}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channel_videos(channel_id, opts \\ []) do

  end

  def get_playlist(playlist_id, opts \\ []) do

  end
end
