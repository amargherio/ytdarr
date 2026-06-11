defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetryTest do
  use Ytdarr.DataCase
  alias Ytdarr.ObanWorkers.VideoDownloaderTelemetry
  alias Ytdarr.Content

  describe "handle_event" do
    test "resets video state on job exception" do
      {:ok, channel} =
        Content.create_channel(%{
          external_id: "telemetry_channel",
          name: "Telemetry Channel",
          url: "https://youtube.com/telemetry_channel"
        })

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "telemetry_video",
          title: "Telemetry Video",
          url: "https://youtube.com/watch?v=telemetry_video",
          download_state: :downloading
        })

      meta = %{
        worker: Ytdarr.ObanWorkers.VideoDownloader,
        args: %{"video_id" => video.id}
      }

      VideoDownloaderTelemetry.handle_event([:oban, :job, :exception], %{}, meta, %{})

      {:ok, updated_video} = Content.get_video(video.id)
      assert updated_video.download_state == :available
    end

    test "resets video state on job cancelled stop" do
      {:ok, channel} =
        Content.create_channel(%{
          external_id: "telemetry_channel_2",
          name: "Telemetry Channel 2",
          url: "https://youtube.com/telemetry_channel_2"
        })

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "telemetry_video_2",
          title: "Telemetry Video 2",
          url: "https://youtube.com/watch?v=telemetry_video_2",
          download_state: :downloading
        })

      meta = %{
        worker: Ytdarr.ObanWorkers.VideoDownloader,
        args: %{"video_id" => video.id},
        state: :cancelled
      }

      VideoDownloaderTelemetry.handle_event([:oban, :job, :stop], %{}, meta, %{})

      {:ok, updated_video} = Content.get_video(video.id)
      assert updated_video.download_state == :available
    end

    test "ignores other workers" do
      meta = %{
        worker: "SomeOtherWorker",
        args: %{"video_id" => 123},
        state: :cancelled
      }

      assert VideoDownloaderTelemetry.handle_event([:oban, :job, :stop], %{}, meta, %{}) == :ok
    end

    test "accepts worker passed as a String" do
      {:ok, channel} =
        Content.create_channel(%{
          external_id: "telemetry_string_channel",
          name: "Telemetry String Channel",
          url: "https://youtube.com/telemetry_string_channel"
        })

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "telemetry_string_video",
          title: "Telemetry String Video",
          url: "https://youtube.com/watch?v=telemetry_string_video",
          download_state: :downloading
        })

      meta = %{
        worker: "Ytdarr.ObanWorkers.VideoDownloader",
        args: %{"video_id" => video.id},
        state: :cancelled
      }

      VideoDownloaderTelemetry.handle_event([:oban, :job, :stop], %{}, meta, %{})

      {:ok, updated_video} = Content.get_video(video.id)
      assert updated_video.download_state == :available
    end

    test "ignores non-terminal stop states (e.g. completed)" do
      meta = %{
        worker: Ytdarr.ObanWorkers.VideoDownloader,
        args: %{"video_id" => 1},
        state: :completed
      }

      assert VideoDownloaderTelemetry.handle_event([:oban, :job, :stop], %{}, meta, %{}) == :ok
    end

    test "no-ops when the referenced video does not exist" do
      meta = %{
        worker: Ytdarr.ObanWorkers.VideoDownloader,
        args: %{"video_id" => 999_999_999},
        state: :cancelled
      }

      assert VideoDownloaderTelemetry.handle_event([:oban, :job, :stop], %{}, meta, %{}) == :ok
    end
  end
end
