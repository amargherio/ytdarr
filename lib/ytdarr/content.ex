defmodule Ytdarr.Content do
  @moduledoc """
  The Content domain handles channels, videos, and playlists.
  """
  use Ash.Domain,
    otp_app: :ytdarr,
    extensions: [AshAdmin.Domain, AshPhoenix]

  alias Ytdarr.Content.{Channel, Video, Playlist}
  alias Ytdarr.Services.YouTube.Client

  require Logger

  admin do
    show? true
  end

  resources do
    resource Channel do
      define :list_channels, action: :read
      define :get_channel, action: :read, get_by: [:id]
      define :get_channel_by_external_id, action: :read, get_by: [:external_id]
      define :create_channel, action: :create
      define :update_channel, action: :update
      define :monitor_channel, action: :monitor
      define :unmonitor_channel, action: :unmonitor
      define :toggle_channel_monitor, action: :toggle_monitor
      define :mark_channel_checked, action: :mark_checked
      define :destroy_channel, action: :destroy
    end

    resource Video do
      define :list_videos, action: :read
      define :get_video, action: :read, get_by: [:id]
      define :get_video_by_external_id, action: :read, get_by: [:external_id]
      define :create_video, action: :create, args: [:channel_id]
      define :update_video, action: :update
      define :mark_video_downloaded, action: :mark_downloaded
      define :destroy_video, action: :destroy
    end

    resource Playlist do
      define :list_playlists, action: :read
      define :get_playlist, action: :read, get_by: [:id]
      define :get_playlist_by_external_id, action: :read, get_by: [:external_id]
      define :create_playlist, action: :create, args: [:channel_id]
      define :update_playlist, action: :update
      define :monitor_playlist, action: :monitor
      define :unmonitor_playlist, action: :unmonitor
      define :toggle_playlist_monitor, action: :toggle_monitor
      define :mark_playlist_checked, action: :mark_checked
      define :destroy_playlist, action: :destroy
    end

    resource Ytdarr.Content.PlaylistVideo
  end

  ## Complex operations that orchestrate syncing

  @doc """
  Sync channel or playlist content with the latest from the source.
  Queues an Oban job to perform the actual sync.
  """
  def sync_content(target_type, target_id) do
    case target_type do
      "channel" ->
        %{"source_type" => "channel", "source_id" => target_id}
        |> Ytdarr.ObanWorkers.SyncWorker.new()
        |> Oban.insert()

      "playlist" ->
        %{"source_type" => "playlist", "source_id" => target_id}
        |> Ytdarr.ObanWorkers.SyncWorker.new()
        |> Oban.insert()

      _ ->
        {:error, :unknown_target_type}
    end
  end

  @doc """
  Sync playlists for a channel from the YouTube API.
  Creates new playlists that don't already exist.
  """
  def sync_channel_playlists(%Channel{} = channel) do
    require Ash.Query

    playlists = Client.get_channel_playlists(channel.external_id)

    Enum.each(playlists, fn pl ->
      case get_playlist_by_external_id(pl.id) do
        {:ok, nil} ->
          create_playlist(channel.id, %{
            external_id: pl.id,
            name: pl.title,
            description: pl.description,
            url: pl.url,
            video_count: pl.video_count,
            is_monitored: false
          })

        {:ok, _existing} ->
          Logger.info("Playlist #{pl.id} already exists, skipping")

        {:error, error} ->
          Logger.error("Error checking playlist #{pl.id}: #{inspect(error)}")
      end
    end)

    {:ok, :synced}
  end

  @doc """
  Fetch latest content from external API (e.g., YouTube).
  Creates playlists and videos for a channel.

  Fetches the upload playlist separately because it isn't included in the channel playlists.
  """
  def sync_channel_content(channel_id) do
    require Ash.Query

    with {:ok, playlists} <- Client.get_channel_playlists(channel_id) do
      Logger.info("Playlist output: #{inspect(playlists)}")
      # Create playlists (excluding uploads)
      sync_playlists(channel_id, playlists)

      # Get videos from uploads playlist
      case Client.get_channel(channel_id) do
        {:ok, channel} ->
          upload_playlist_id = channel.uploads_playlist_id
          sync_uploads_videos(channel_id, upload_playlist_id)
        {:error, reason} ->
          Logger.error("Error fetching channel data for #{channel_id}: #{inspect(reason)}")
      end

      {:ok, :synced}
    end
  end

  defp sync_playlists(channel_id, playlists) do
    with {:ok, channel} <- get_channel_by_external_id(channel_id),
         true <- not is_nil(channel) do
      Enum.each(playlists, fn pl ->
        Logger.info("Processing playlist #{pl.id} - #{pl.title}")
        case get_playlist_by_external_id(pl.id) do
          {:ok, nil} ->
            create_playlist(channel.id, %{
              external_id: pl.id,
              name: pl.title,
              description: pl.description,
              url: pl.url,
              video_count: pl.video_count,
              is_monitored: false
            })

          {:ok, _existing} ->
            Logger.info("Playlist #{pl.id} already exists, skipping")

          {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} ->
            create_playlist(channel.id, %{
              external_id: pl.id,
              name: pl.title,
              description: pl.description,
              url: pl.url,
              video_count: pl.video_count,
              is_monitored: false
            })

          {:error, error} ->
            Logger.error("Error checking playlist #{pl.id}: #{inspect(error)}")
        end
      end)
    else
      _ -> Logger.error("Channel not found for external_id: #{channel_id}")
    end
  end

  defp sync_uploads_videos(_channel_id, nil), do: :ok

  defp sync_uploads_videos(channel_id, uploads_playlist_id) do
    with {:ok, playlist_detailed} <- Client.get_playlist_items_detailed(uploads_playlist_id) do
      Logger.info("Got playlist details with videos and pagination for larger payloads: #{inspect(playlist_detailed)}")
      Logger.debug("Videos to sync: #{inspect(playlist_detailed.videos)}")

      Enum.each(playlist_detailed.videos, fn vid ->
        Logger.debug("Processing video #{vid.id} - #{vid.title} (playlist item ID: #{vid.playlist_item_id})")
        case get_video_by_external_id(vid.id) do
          {:ok, nil} ->
            create_video(channel_id, %{
              external_id: vid.id,
              title: vid.title,
              description: vid.description,
              url: vid.url,
              thumbnail_url: vid.thumbnail_url,
              upload_date: vid.published_at,
              duration: vid.duration,
              discovered_from: "uploads"
            })

          {:ok, _existing} ->
            Logger.info("Video #{vid.id} already exists, skipping")

          {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} ->
            create_video(channel_id, %{
              external_id: vid.id,
              title: vid.title,
              description: vid.description,
              url: vid.url,
              thumbnail_url: vid.thumbnail_url,
              upload_date: vid.published_at,
              duration: vid.duration,
              discovered_from: "uploads"
            })

          {:error, error} ->
            Logger.error("Error checking video #{vid.id}: #{inspect(error)}")
        end
      end)
    end
  end

  @doc """
  Queue a video for download via Oban
  """
  def queue_video_download(video_id, channel_id) do
    %{"video_id" => video_id, "channel_id" => channel_id}
    |> Ytdarr.ObanWorkers.VideoDownloader.new()
    |> Oban.insert()
  end

  @doc"""
  Associate playlists and videos

  ## Parameters
    - playlist_id: Internal ID of the playlist to associate videos for
  """
  def associate_playlists_and_videos(playlist_id) do
    require Ash.Query
    alias Ytdarr.Content.PlaylistVideo

    {:ok, playlist} = get_playlist(playlist_id)
    videos = Client.get_playlist_videos(playlist.external_id)

    # For each video, query if it's in the DB. If it is, verify the association exists, if not create it
    Enum.each(videos, fn vid ->
      case get_video_by_external_id(vid.id) do
        {:ok, existing_vid} when not is_nil(existing_vid) ->
          # Check if association exists using Ash.Query
          case Ash.read(
                 Ash.Query.filter(PlaylistVideo, playlist_id == ^playlist.id and video_id == ^existing_vid.id)
               ) do
            {:ok, []} ->
              # Create association using Ash.create
              Ash.create(PlaylistVideo, %{playlist_id: playlist.id, video_id: existing_vid.id})

            {:ok, _existing} ->
              # Association already exists, skip
              :ok

            {:error, error} ->
              Logger.error("Error checking playlist_video association: #{inspect(error)}")
          end

        _ ->
          # Video doesn't exist, skip
          :ok
      end
    end)

    {:ok, :associated}
  end

  def create_jellyfin_collection_from_playlist(playlist_id) do
    Oban.insert(%Oban.Job{
      worker: Ytdarr.ObanWorkers.JellyfinCollectionCreator,
      args: %{"playlist_id" => playlist_id}
    })
  end
end
