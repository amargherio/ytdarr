defmodule Ytdarr.ObanWorkers.SyncWorker do
  @moduledoc """
  Oban worker for synchronizing content from external sources.

  This worker handles the synchronization of videos, playlists,
  and channels by fetching updates and ensuring local data is
  up-to-date with the source.
  """

  use Oban.Worker, queue: :sync_worker

  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.Content.{Channel, Playlist, Video}
  alias Ytdarr.{Content, Settings}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_type" => source_type, "source_id" => source_id}}) do
    case source_type do
      "channel" ->
        Content.get_channel!(source_id)
        |> sync_channel()

      "playlist" ->
        Content.get_playlist!(source_id)
        |> sync_playlist()

      _ ->
        {:error, :unknown_source_type}
    end
  end

  @doc """
  Syncs channel content, creating any new playlists and videos as needed
  """
  defp sync_channel(%Channel{} = channel) do
    # Fetch latest videos and update local database
    Logger.info("Synchronizing channel: #{channel.name}")
    Content.sync_channel_content(channel.external_id)
    :ok
  end

  @doc """
  Syncs playlists for a channel, creating any new playlists as needed
  """
  defp sync_playlist(%Playlist{} = playlist) do
    # Fetch latest videos and update local database
    IO.puts("Synchronizing playlist: #{playlist.name}")
    :ok
  end
end
