defmodule Ytdarr.Content.VideoTest do
  use Ytdarr.DataCase

  import Ytdarr.ContentFixtures

  alias Ash.Error.Changes.Required
  alias Ytdarr.Content

  @empty_recovery %{"mode" => nil, "entries" => []}

  describe "create_video/2" do
    test "creates with valid attributes" do
      channel = channel_fixture()
      attrs = video_attrs()

      assert {:ok, video} = Content.create_video(channel.id, attrs)
      assert video.channel_id == channel.id
      assert video.title == attrs.title
      assert video.external_id == attrs.external_id
      refute video.is_blocklisted
      assert video.import_recovery == @empty_recovery
    end

    test "fails when required attributes or channel_id are nil" do
      channel = channel_fixture()
      attrs = video_attrs()

      for field <- [:title, :external_id, :url] do
        result = Content.create_video(channel.id, Map.put(attrs, field, nil))
        assert_required_error(result, field, :attribute)
      end

      assert_required_error(Content.create_video(nil, attrs), :channel_id, :argument)
    end
  end

  describe "video blocklist" do
    test "blocklists and unblocks a video idempotently" do
      video = video_fixture()

      assert {:ok, blocked_video} = Content.blocklist_video(video)
      assert blocked_video.is_blocklisted

      assert {:ok, blocked_video} = Content.blocklist_video(blocked_video)
      assert blocked_video.is_blocklisted

      assert {:ok, unblocked_video} = Content.unblocklist_video(blocked_video)
      refute unblocked_video.is_blocklisted
    end

    test "upserting metadata preserves an existing blocklist flag" do
      video = video_fixture()
      assert {:ok, blocked_video} = Content.blocklist_video(video)

      assert {:ok, updated_video} =
               Content.upsert_video(blocked_video.channel_id, %{
                 external_id: blocked_video.external_id,
                 title: "Updated title",
                 url: blocked_video.url,
                 is_blocklisted: false
               })

      assert updated_video.title == "Updated title"
      assert updated_video.is_blocklisted
    end
  end

  describe "download lifecycle" do
    test "allows only the guarded download sequence" do
      video = video_fixture()

      assert {:ok, queued} = Content.begin_video_download(video)
      assert queued.download_state == :queued
      refute queued.is_downloaded

      assert {:ok, downloading} = Content.start_video_download(queued)
      assert downloading.download_state == :downloading

      assert {:ok, downloaded} =
               Content.mark_video_downloaded(downloading, %{
                 download_path: "/downloads/test-video.mp4",
                 file_size: 123_456,
                 download_quality: "1080p"
               })

      assert downloaded.is_downloaded
      assert downloaded.download_state == :downloaded
      assert downloaded.download_path == "/downloads/test-video.mp4"
      assert %DateTime{} = downloaded.downloaded_at
      assert downloaded.import_recovery == @empty_recovery

      assert {:ok, reset} = Content.reset_video_downloaded(downloaded)
      assert reset.download_state == :available
      refute reset.is_downloaded
      assert is_nil(reset.download_path)
      assert is_nil(reset.downloaded_at)
      assert is_nil(reset.file_size)
      assert is_nil(reset.download_quality)
    end

    test "rejects stale and generic lifecycle writes" do
      video = video_fixture()

      assert {:error, _} = Content.start_video_download(video)

      assert {:error, _} =
               Content.mark_video_downloaded(video, %{download_path: "/tmp/video.mp4"})

      assert {:error, _} = Content.reset_video_downloaded(video)
      assert {:error, _} = Content.update_video(video, %{download_state: :queued})
      assert {:error, _} = Content.update_video(video, %{download_path: "/tmp/video.mp4"})
      assert {:error, _} = Content.update_video(video, %{import_error: "not accepted"})
      assert {:error, _} = Content.update_video(video, %{import_recovery: @empty_recovery})
    end

    test "resets only queued or downloading work and accepts a missing video" do
      queued_video = video_fixture()
      assert {:ok, queued} = Content.begin_video_download(queued_video)
      assert {:ok, reset_queued} = Content.reset_video_download(queued)
      assert reset_queued.download_state == :available

      downloading_video = video_fixture()
      assert {:ok, queued} = Content.begin_video_download(downloading_video)
      assert {:ok, downloading} = Content.start_video_download(queued)
      assert {:ok, reset_downloading} = Content.reset_video_download(downloading)
      assert reset_downloading.download_state == :available

      channel = channel_fixture()

      assert {:ok, missing} =
               Content.create_video(channel.id, video_attrs(%{download_state: :missing}))

      assert {:ok, queued_missing} = Content.begin_video_download(missing)
      assert queued_missing.download_state == :queued
    end
  end

  describe "import lifecycle" do
    test "persists a delete journal only after an importing video is marked imported" do
      video = video_fixture()
      manifest = %{"source" => "/tmp/source.mkv"}
      recovery = %{"mode" => "delete", "entries" => [%{"path" => "/tmp/stage"}]}

      assert {:ok, importing} =
               Content.begin_video_import(video, %{import_job_id: 41, import_manifest: manifest})

      assert importing.download_state == :importing
      assert importing.import_job_id == 41
      assert importing.import_manifest == manifest

      assert {:ok, imported} =
               Content.mark_video_imported(importing, %{
                 download_path: "/downloads/imported.mkv",
                 file_size: 42,
                 download_quality: "1080p",
                 import_recovery: recovery
               })

      assert imported.download_state == :downloaded
      assert imported.is_downloaded
      assert imported.import_recovery == recovery
      assert is_nil(imported.import_job_id)
      assert is_nil(imported.import_manifest)
      assert is_nil(imported.import_error)
    end

    test "blocks a new import or download until restore recovery is empty" do
      video = video_fixture()
      recovery = %{"mode" => "restore", "entries" => [%{"path" => "/tmp/quarantine"}]}

      assert {:ok, importing} =
               Content.begin_video_import(video, %{
                 import_job_id: 42,
                 import_manifest: %{"source" => "x"}
               })

      assert {:ok, failed} =
               Content.mark_video_import_failed(importing, %{
                 import_error:
                   "Ytdarr could not import this file. Check the server logs and try again.",
                 import_recovery: recovery
               })

      assert failed.download_state == :import_failed
      assert failed.import_recovery == recovery

      assert {:error, _} =
               Content.begin_video_import(failed, %{import_job_id: 43, import_manifest: %{}})

      assert {:error, _} = Content.begin_video_download(failed)

      assert {:ok, recovered} =
               Content.update_video_import_recovery(failed, %{import_recovery: @empty_recovery})

      assert {:ok, queued} = Content.begin_video_download(recovered)
      assert queued.download_state == :queued
    end

    test "permits recovery updates only after import reaches a terminal state" do
      video = video_fixture()

      assert {:ok, importing} =
               Content.begin_video_import(video, %{import_job_id: 44, import_manifest: %{}})

      assert {:error, _} =
               Content.update_video_import_recovery(importing, %{import_recovery: @empty_recovery})
    end

    test "preserves an existing blocklist while beginning an import" do
      video = video_fixture(%{is_blocklisted: true})

      assert {:ok, importing} =
               Content.begin_video_import(video, %{
                 import_job_id: 45,
                 import_manifest: %{"source" => "x"}
               })

      assert importing.download_state == :importing
      assert importing.is_blocklisted
    end

    test "rejects unsafe import errors longer than the persisted limit" do
      video = video_fixture()

      assert {:ok, importing} =
               Content.begin_video_import(video, %{
                 import_job_id: 46,
                 import_manifest: %{"source" => "x"}
               })

      assert {:error, _} =
               Content.mark_video_import_failed(importing, %{
                 import_error: String.duplicate("x", 501),
                 import_recovery: @empty_recovery
               })
    end
  end

  describe "SetDiscoveredFields" do
    test "sets discovered_at and uploads position when discovered_from is uploads" do
      channel = channel_fixture()

      assert {:ok, video} =
               Content.create_video(channel.id, video_attrs(%{discovered_from: "uploads"}))

      assert %DateTime{} = video.discovered_at
      assert video.position_in_uploads == 0
    end
  end

  defp video_attrs(overrides \\ %{}) do
    unique_id = System.unique_integer([:positive])

    Enum.into(overrides, %{
      title: "Test Video #{unique_id}",
      external_id: "video-#{unique_id}",
      url: "https://www.youtube.com/watch?v=video#{unique_id}",
      description: "Video description",
      upload_date: Date.utc_today(),
      duration: 600
    })
  end

  defp assert_required_error({:error, %Ash.Error.Invalid{errors: errors}}, field, type) do
    assert Enum.any?(errors, fn
             %Required{field: ^field, type: ^type} -> true
             _ -> false
           end)
  end
end
