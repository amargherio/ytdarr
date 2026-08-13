defmodule Ytdarr.ObanWorkers.VideoImporterTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.VideoImporter
  alias __MODULE__.{ImporterImports, ImporterVideoImport}

  @empty_recovery %{"mode" => nil, "entries" => []}

  test "stages, persists downloaded state, cleans ownership, then broadcasts completion" do
    {video, job} = importing_job(:success)

    assert :ok =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    channel_id = video.channel_id
    video_id = video.id
    assert_receive {:import_event, {:video_import_completed, ^channel_id, ^video_id}}, 100

    assert {:ok, imported} = Content.get_video(video.id)
    assert imported.download_state == :downloaded
    assert imported.download_path == job.args["destination_path"]
    assert imported.file_size == 123
    assert imported.download_quality == "1080p"
    assert imported.import_recovery == @empty_recovery
  end

  test "persists restore evidence and a safe error before cancelling a stage failure" do
    {video, job} = importing_job(:stage_failure)

    assert {:cancel, :source_changed} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    channel_id = video.channel_id
    video_id = video.id
    message = "The selected file changed. Select it again."
    assert_receive {:import_event, {:video_import_failed, ^channel_id, ^video_id, ^message}}, 100

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed

    assert failed.import_recovery == %{
             "mode" => "restore",
             "entries" => [%{"path" => "/tmp/restore"}]
           }

    assert is_nil(failed.import_job_id)
    assert is_nil(failed.import_manifest)
  end

  test "keeps a delete journal and broadcasts a cleanup warning when cleanup is incomplete" do
    {video, job} = importing_job(:cleanup_failure)

    assert :ok =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    channel_id = video.channel_id
    video_id = video.id
    assert_receive {:import_event, {:video_import_cleanup_warning, ^channel_id, ^video_id}}, 100

    assert {:ok, imported} = Content.get_video(video.id)
    assert imported.download_state == :downloaded

    assert imported.import_recovery == %{
             "mode" => "delete",
             "entries" => [%{"path" => "/tmp/cleanup"}]
           }
  end

  test "does not overwrite a newer lifecycle state when the job id is stale" do
    {video, job} = importing_job(:success)
    stale_job = %{job | id: job.id + 1}

    assert {:cancel, :video_not_importable} =
             VideoImporter.run(stale_job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    refute_receive {:import_event, _}
    assert {:ok, importing} = Content.get_video(video.id)
    assert importing.download_state == :importing
    assert importing.import_job_id == job.id
  end

  defp importing_job(outcome) do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})
    job_id = System.unique_integer([:positive])

    manifest = %{
      "source_path" => "/tmp/source-#{job_id}.mkv",
      "destination_path" => "/tmp/destination-#{job_id}.mkv",
      "outcome" => Atom.to_string(outcome)
    }

    assert {:ok, _importing} =
             Content.begin_video_import(video, %{import_job_id: job_id, import_manifest: manifest})

    {video,
     %Oban.Job{
       id: job_id,
       worker: "Ytdarr.ObanWorkers.VideoImporter",
       args: %{
         "video_id" => video.id,
         "channel_id" => channel.id,
         "source_path" => manifest["source_path"],
         "destination_path" => manifest["destination_path"],
         "manifest" => manifest
       }
     }}
  end

  defmodule ImporterImports do
    def broadcast(event) do
      send(self(), {:import_event, event})
      :ok
    end
  end

  defmodule ImporterVideoImport do
    defmodule Manifest do
      def from_map(%{"source_path" => source_path, "destination_path" => destination_path} = map) do
        {:ok,
         %{
           source: %{source_path: source_path},
           destination: %{media_path: destination_path},
           outcome: Map.get(map, "outcome", "success")
         }}
      end
    end

    def stage(_job_id, manifest, _channel, _video) do
      case manifest.outcome do
        "stage_failure" -> {:error, :source_changed, [%{"path" => "/tmp/restore"}]}
        outcome -> {:ok, %{file_size: 123, quality: "1080p", outcome: outcome}}
      end
    end

    def recovery_map(_placement, :delete),
      do: %{"mode" => "delete", "entries" => [%{"path" => "/tmp/stage"}]}

    def recovery_map(_placement, :restore),
      do: %{"mode" => "restore", "entries" => [%{"path" => "/tmp/restore"}]}

    def rollback(_placement), do: {:ok, []}
    def commit_cleanup(%{outcome: "cleanup_failure"}), do: {:error, [%{"path" => "/tmp/cleanup"}]}
    def commit_cleanup(_placement), do: {:ok, []}
  end
end
