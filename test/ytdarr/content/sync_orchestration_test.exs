defmodule Ytdarr.Content.SyncOrchestrationTest do
  @moduledoc """
  Tests for `Ytdarr.Content` orchestration paths that do not require live
  YouTube API access: local omnisearch, sync_content dispatch, and the
  error branches of sync_channel_content / sync_playlist_content.
  """
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.SyncWorker

  describe "omnisearch/1" do
    test "returns empty results for queries shorter than 2 characters" do
      assert Content.omnisearch("") == %{channels: [], playlists: [], videos: []}
      assert Content.omnisearch("a") == %{channels: [], playlists: [], videos: []}
    end

    test "returns matching channels, playlists, and videos" do
      channel = channel_fixture(%{name: "Omnisearch Channel"})
      playlist = playlist_fixture(%{channel_id: channel.id, name: "Omnisearch Playlist"})
      video = video_fixture(%{channel_id: channel.id, title: "Omnisearch Video"})

      results = Content.omnisearch("Omnisearch")

      assert Enum.any?(results.channels, &(&1.id == channel.id))
      assert Enum.any?(results.playlists, &(&1.id == playlist.id))
      assert Enum.any?(results.videos, &(&1.id == video.id))
    end

    test "limits each bucket to 5 results" do
      for i <- 1..6 do
        channel_fixture(%{name: "BulkOmni Channel #{i}"})
      end

      results = Content.omnisearch("BulkOmni")
      assert length(results.channels) == 5
    end
  end

  describe "sync_content/2" do
    test "enqueues a SyncWorker job for channel targets" do
      channel = channel_fixture()
      assert {:ok, _job} = Content.sync_content("channel", channel.id)

      assert_enqueued(
        worker: SyncWorker,
        args: %{"source_type" => "channel", "source_id" => channel.id}
      )
    end

    test "enqueues a SyncWorker job for playlist targets" do
      playlist = playlist_fixture()
      assert {:ok, _job} = Content.sync_content("playlist", playlist.id)

      assert_enqueued(
        worker: SyncWorker,
        args: %{"source_type" => "playlist", "source_id" => playlist.id}
      )
    end

    test "returns :unknown_target_type for unrecognized target types" do
      assert {:error, :unknown_target_type} = Content.sync_content("unknown", 42)
      assert {:error, :unknown_target_type} = Content.sync_content("video", 42)
    end
  end

  describe "sync_channel_content/1" do
    test "returns an error when the external id has no matching record" do
      assert {:error, %Ash.Error.Invalid{}} =
               Content.sync_channel_content(
                 "UC_DOES_NOT_EXIST_#{System.unique_integer([:positive])}"
               )
    end
  end

  describe "sync_playlist_content/1" do
    test "returns :not_found when the playlist id does not exist" do
      assert {:error, _} = Content.sync_playlist_content(999_999_999)
    end
  end

  describe "queue_video_download/2" do
    test "returns an error when the video does not exist" do
      assert {:error, _} = Content.queue_video_download(999_999_999, 1)
    end
  end

  describe "delete_video_file/1" do
    test "treats a missing physical file as already deleted" do
      channel = channel_fixture()

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "delete-missing-#{System.unique_integer([:positive])}",
          title: "Missing File Video",
          url: "https://example.com/missing",
          download_state: :downloaded,
          is_downloaded: true,
          download_path: "/tmp/never-existed-#{System.unique_integer([:positive])}.mp4"
        })

      assert {:ok, updated} = Content.delete_video_file(video.id)
      assert updated.download_state == :available
      refute updated.is_downloaded
      assert is_nil(updated.download_path)
    end

    test "resets state when video has no download_path" do
      channel = channel_fixture()

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "delete-no-path-#{System.unique_integer([:positive])}",
          title: "Pathless Video",
          url: "https://example.com/pathless",
          download_state: :available
        })

      assert {:ok, updated} = Content.delete_video_file(video.id)
      assert updated.download_state == :available
    end
  end

  describe "form_to_create_channel/0 and form_to_update_channel/1" do
    test "create form is built for the Channel resource" do
      form = Content.form_to_create_channel()
      assert %AshPhoenix.Form{resource: Ytdarr.Content.Channel, action: :create} = form
    end

    test "update form is built for an existing channel" do
      channel = channel_fixture()
      form = Content.form_to_update_channel(channel)
      assert %AshPhoenix.Form{resource: Ytdarr.Content.Channel, action: :update} = form
    end
  end

  describe "upsert_and_link_playlist_entries/2" do
    test "creates videos and PlaylistVideo links from API entries" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      {:ok, loaded_playlist} = Ash.load(playlist, :channel)

      entries = [
        %{
          "video_details" => %{
            "id" => "vid-link-1-#{System.unique_integer([:positive])}",
            "snippet" => %{
              "title" => "Linked Video 1",
              "description" => "From API entry",
              "publishedAt" => "2025-01-15T00:00:00Z",
              "thumbnails" => %{"high" => %{"url" => "https://example.com/t1.jpg"}}
            },
            "contentDetails" => %{"duration" => "PT5M30S"}
          }
        },
        %{
          "video_details" => %{
            "id" => "vid-link-2-#{System.unique_integer([:positive])}",
            "snippet" => %{
              "title" => "Linked Video 2",
              "description" => "Another entry",
              "publishedAt" => "2025-01-16T00:00:00Z",
              "thumbnails" => %{"default" => %{"url" => "https://example.com/t2.jpg"}}
            },
            "contentDetails" => %{"duration" => "PT2H15M"}
          }
        }
      ]

      assert :ok = Content.upsert_and_link_playlist_entries(loaded_playlist, entries)
    end

    test "skips entries without a video id" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      {:ok, loaded_playlist} = Ash.load(playlist, :channel)

      entries = [%{"video_details" => %{}}, %{}]

      assert :ok = Content.upsert_and_link_playlist_entries(loaded_playlist, entries)
    end
  end
end
