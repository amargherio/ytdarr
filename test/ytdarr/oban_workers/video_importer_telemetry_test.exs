defmodule Ytdarr.ObanWorkers.VideoImporterTelemetryTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.VideoImporterTelemetry
  alias __MODULE__.{TelemetryImports, TelemetryVideoImport}

  test "recovers a still-importing video from real job exception metadata" do
    {video, job} = importing_video("exception")

    assert :ok =
             VideoImporterTelemetry.handle_event(
               [:oban, :job, :exception],
               %{},
               %{job: job, state: :failure, reason: :source_changed},
               telemetry_config()
             )

    channel_id = video.channel_id
    video_id = video.id
    message = "The selected file changed. Select it again."

    assert_receive {:telemetry_import_event,
                    {:video_import_failed, ^channel_id, ^video_id, ^message}}

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
    assert failed.import_recovery == %{"mode" => nil, "entries" => []}
  end

  test "handles terminal stop cancellation with the actual nested job shape" do
    {video, job} = importing_video("cancel")

    assert :ok =
             VideoImporterTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: job, state: :cancelled},
               telemetry_config()
             )

    video_id = video.id
    assert_receive {:telemetry_import_event, {:video_import_failed, _, ^video_id, _}}
    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
  end

  test "handles a nonexecuting single engine cancellation" do
    {video, job} = importing_video("engine-single")
    job = %{job | state: "available"}

    assert :ok =
             VideoImporterTelemetry.handle_event(
               [:oban, :engine, :cancel_job, :stop],
               %{},
               %{job: job},
               telemetry_config()
             )

    video_id = video.id
    assert_receive {:telemetry_import_event, {:video_import_failed, _, ^video_id, _}}
    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
  end

  test "uses persisted import_job_id for a bulk engine cancellation" do
    {video, job} = importing_video("engine-bulk")

    assert :ok =
             VideoImporterTelemetry.handle_event(
               [:oban, :engine, :delete_all_jobs, :stop],
               %{},
               %{jobs: [%{id: job.id, queue: "video_importer", state: "available"}]},
               telemetry_config()
             )

    video_id = video.id
    assert_receive {:telemetry_import_event, {:video_import_failed, _, ^video_id, _}}
    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
  end

  test "does not recover an executing engine job and only warns after a downloaded commit" do
    {video, job} = importing_video("stale")
    imported = mark_imported(video, job.id)

    assert :ok =
             VideoImporterTelemetry.handle_event(
               [:oban, :engine, :cancel_job, :stop],
               %{},
               %{job: %{job | state: "executing"}},
               telemetry_config()
             )

    refute_receive {:telemetry_import_event, _}

    assert :ok =
             VideoImporterTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: job, state: :cancelled},
               telemetry_config()
             )

    channel_id = imported.channel_id
    imported_video_id = imported.id

    assert_receive {:telemetry_import_event,
                    {:video_import_cleanup_warning, ^channel_id, ^imported_video_id}}

    assert {:ok, fresh} = Content.get_video(video.id)
    assert fresh.download_state == :downloaded
  end

  defp importing_video(label) do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})
    job_id = System.unique_integer([:positive])
    manifest = %{"label" => label}

    assert {:ok, _importing} =
             Content.begin_video_import(video, %{import_job_id: job_id, import_manifest: manifest})

    {video,
     %Oban.Job{
       id: job_id,
       worker: "Ytdarr.ObanWorkers.VideoImporter",
       args: %{"video_id" => video.id, "manifest" => manifest}
     }}
  end

  defp mark_imported(video, job_id) do
    assert {:ok, importing} = Content.get_video(video.id)
    assert importing.import_job_id == job_id

    assert {:ok, imported} =
             Content.mark_video_imported(importing, %{
               download_path: "/tmp/imported-#{job_id}.mkv",
               file_size: 12,
               download_quality: "1080p",
               import_recovery: %{"mode" => "delete", "entries" => [%{"path" => "/tmp/marker"}]}
             })

    imported
  end

  defp telemetry_config do
    %{content: Content, imports: TelemetryImports, video_import: TelemetryVideoImport}
  end

  defmodule TelemetryImports do
    def broadcast(event) do
      send(self(), {:telemetry_import_event, event})
      :ok
    end
  end

  defmodule TelemetryVideoImport do
    defmodule Manifest do
      def from_map(_map), do: {:ok, %{}}
    end

    def recover(_job_id, _manifest, :importing), do: {:ok, []}
  end
end
