defmodule Ytdarr.ObanWorkers.VideoImporterTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.VideoImporter

  alias __MODULE__.{
    CleanupPersistenceFailureContent,
    ConcurrentCommitContent,
    FailurePersistenceUnavailableContent,
    ImporterImports,
    ImporterVideoImport,
    MissingVideoContent,
    PlacementPersistenceFailureContent,
    ReloadUnavailableContent
  }

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

  test "leaves the video ready for another import when staging changed nothing" do
    {video, job} = importing_job(:empty_stage_failure)

    assert {:cancel, :source_changed} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
    assert failed.import_recovery == @empty_recovery

    assert {:ok, retried} =
             Content.begin_video_import(failed, %{
               import_job_id: System.unique_integer([:positive]),
               import_manifest: %{"source" => "retry"}
             })

    assert retried.download_state == :importing
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
    assert_receive {:import_event, {:video_import_failed, ^channel_id, ^video_id, message}}, 100
    refute String.contains?(message, "source_changed")
    refute String.contains?(message, job.args["source_path"])

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

  test "cancels malformed worker arguments through the public Oban callback" do
    job = %Oban.Job{id: System.unique_integer([:positive]), args: %{}}

    assert {:cancel, :invalid_import_job} = VideoImporter.perform(job)
  end

  test "cancels a job whose video was deleted before it ran" do
    job = %Oban.Job{
      id: System.unique_integer([:positive]),
      args: %{"video_id" => System.unique_integer([:positive]), "channel_id" => 1}
    }

    assert {:cancel, :not_found} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: MissingVideoContent,
               imports: ImporterImports
             )
  end

  test "fails the import when the job paths no longer match its manifest" do
    {video, job} = importing_job(:success)
    changed_job = put_in(job.args["source_path"], "/tmp/replaced-source.mkv")

    assert {:cancel, :source_changed} =
             VideoImporter.run(changed_job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
    assert failed.import_recovery == @empty_recovery
  end

  test "keeps the imported ownership journal when cleanup completion cannot be saved" do
    {video, job} = importing_job(:cleanup_persistence_failure)

    assert :ok =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: CleanupPersistenceFailureContent,
               imports: ImporterImports
             )

    video_id = video.id
    assert_receive {:import_event, {:video_import_cleanup_warning, _, ^video_id}}, 100

    assert {:ok, imported} = Content.get_video(video.id)
    assert imported.download_state == :downloaded

    assert imported.import_recovery == %{
             "mode" => "delete",
             "entries" => [%{"path" => "/tmp/stage"}]
           }
  end

  test "keeps the existing journal when recording cleanup failures is unavailable" do
    {video, job} = importing_job(:cleanup_journal_persistence_failure)

    assert :ok =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: CleanupPersistenceFailureContent,
               imports: ImporterImports
             )

    video_id = video.id
    assert_receive {:import_event, {:video_import_cleanup_warning, _, ^video_id}}, 100

    assert {:ok, imported} = Content.get_video(video.id)
    assert imported.download_state == :downloaded

    assert imported.import_recovery == %{
             "mode" => "delete",
             "entries" => [%{"path" => "/tmp/stage"}]
           }
  end

  test "warns without discarding ownership evidence for an unknown cleanup result" do
    {video, job} = importing_job(:unexpected_cleanup)

    assert :ok =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: Content,
               imports: ImporterImports
             )

    video_id = video.id
    assert_receive {:import_event, {:video_import_cleanup_warning, _, ^video_id}}, 100

    assert {:ok, imported} = Content.get_video(video.id)
    assert imported.download_state == :downloaded

    assert imported.import_recovery == %{
             "mode" => "delete",
             "entries" => [%{"path" => "/tmp/stage"}]
           }
  end

  test "records restore evidence when placement persistence fails and rollback is incomplete" do
    {video, job} = importing_job(:rollback_failure)

    assert {:cancel, :persistence_unavailable} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: PlacementPersistenceFailureContent,
               imports: ImporterImports
             )

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed

    assert failed.import_recovery == %{
             "mode" => "restore",
             "entries" => [%{"path" => "/tmp/rollback"}]
           }
  end

  test "uses the stage recovery map when rollback returns an unknown result" do
    {video, job} = importing_job(:unexpected_rollback)

    assert {:cancel, :persistence_unavailable} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: PlacementPersistenceFailureContent,
               imports: ImporterImports
             )

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed

    assert failed.import_recovery == %{
             "mode" => "restore",
             "entries" => [%{"path" => "/tmp/restore"}]
           }
  end

  test "does not hide an import failure when its failure record cannot be persisted" do
    {video, job} = importing_job(:success)

    assert {:cancel, :persistence_unavailable} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: FailurePersistenceUnavailableContent,
               imports: ImporterImports
             )

    refute_receive {:import_event, _}
    assert {:ok, importing} = Content.get_video(video.id)
    assert importing.download_state == :importing
  end

  test "cancels safely when the importing record disappears during failure recovery" do
    {video, job} = importing_job(:stage_failure)
    Process.put(:importer_reload_id, video.id)

    on_exit(fn ->
      Process.delete(:importer_reload_id)
      Process.delete(:importer_loaded?)
    end)

    assert {:cancel, :source_changed} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: ReloadUnavailableContent,
               imports: ImporterImports
             )

    refute_receive {:import_event, _}
    assert {:ok, importing} = Content.get_video(video.id)
    assert importing.download_state == :importing
  end

  test "warns when a concurrent imported commit makes a failed placement stale" do
    {video, job} = importing_job(:success)

    assert {:cancel, :concurrent_commit} =
             VideoImporter.run(job,
               video_import: ImporterVideoImport,
               content: ConcurrentCommitContent,
               imports: ImporterImports
             )

    video_id = video.id
    assert_receive {:import_event, {:video_import_cleanup_warning, _, ^video_id}}, 100

    assert {:ok, imported} = Content.get_video(video.id)
    assert imported.download_state == :downloaded

    assert imported.import_recovery == %{
             "mode" => "delete",
             "entries" => [%{"path" => "/tmp/stage"}]
           }
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

  defmodule MissingVideoContent do
    def get_video(_video_id), do: {:error, :not_found}
  end

  defmodule CleanupPersistenceFailureContent do
    def get_video(video_id), do: Content.get_video(video_id)
    def get_channel(channel_id), do: Content.get_channel(channel_id)
    def mark_video_imported(video, attrs), do: Content.mark_video_imported(video, attrs)
    def update_video_import_recovery(_video, _attrs), do: {:error, :persistence_unavailable}
  end

  defmodule PlacementPersistenceFailureContent do
    def get_video(video_id), do: Content.get_video(video_id)
    def get_channel(channel_id), do: Content.get_channel(channel_id)
    def mark_video_imported(_video, _attrs), do: {:error, :persistence_unavailable}
    def mark_video_import_failed(video, attrs), do: Content.mark_video_import_failed(video, attrs)
  end

  defmodule FailurePersistenceUnavailableContent do
    def get_video(video_id), do: Content.get_video(video_id)
    def get_channel(channel_id), do: Content.get_channel(channel_id)
    def mark_video_imported(_video, _attrs), do: {:error, :persistence_unavailable}
    def mark_video_import_failed(_video, _attrs), do: {:error, :persistence_unavailable}
  end

  defmodule ReloadUnavailableContent do
    def get_video(video_id) do
      if Process.get(:importer_reload_id) == video_id and Process.get(:importer_loaded?) do
        {:error, :not_found}
      else
        Process.put(:importer_loaded?, true)
        Content.get_video(video_id)
      end
    end

    def get_channel(channel_id), do: Content.get_channel(channel_id)
  end

  defmodule ConcurrentCommitContent do
    def get_video(video_id), do: Content.get_video(video_id)
    def get_channel(channel_id), do: Content.get_channel(channel_id)

    def mark_video_imported(video, attrs) do
      {:ok, _imported} = Content.mark_video_imported(video, attrs)
      {:error, :concurrent_commit}
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
        "empty_stage_failure" -> {:error, :source_changed}
        outcome -> {:ok, %{file_size: 123, quality: "1080p", outcome: outcome}}
      end
    end

    def recovery_map(_placement, :delete),
      do: %{"mode" => "delete", "entries" => [%{"path" => "/tmp/stage"}]}

    def recovery_map(_placement, :restore),
      do: %{"mode" => "restore", "entries" => [%{"path" => "/tmp/restore"}]}

    def rollback(%{outcome: "rollback_failure"}), do: {:error, [%{"path" => "/tmp/rollback"}]}
    def rollback(%{outcome: "unexpected_rollback"}), do: :unknown
    def rollback(_placement), do: {:ok, []}

    def commit_cleanup(%{outcome: "cleanup_failure"}), do: {:error, [%{"path" => "/tmp/cleanup"}]}

    def commit_cleanup(%{outcome: "cleanup_journal_persistence_failure"}),
      do: {:error, [%{"path" => "/tmp/cleanup"}]}

    def commit_cleanup(%{outcome: "unexpected_cleanup"}), do: :unknown
    def commit_cleanup(_placement), do: {:ok, []}
  end
end
