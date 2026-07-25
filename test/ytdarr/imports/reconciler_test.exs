defmodule Ytdarr.Imports.ReconcilerTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.{Content, Repo}
  alias Ytdarr.Imports.Reconciler
  alias __MODULE__.{ReconcilerImports, ReconcilerVideoImport}

  test "recovers every stale executing importer before cancelling its job row" do
    {video, job} = importing_job("executing")

    assert :ok = Reconciler.reconcile(reconciler_opts())

    channel_id = video.channel_id
    video_id = video.id
    assert_receive {:reconciler_import_event, {:video_import_failed, ^channel_id, ^video_id, _}}

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"
  end

  test "leaves an available importer for Oban to execute" do
    {video, job} = importing_job("available")

    assert :ok = Reconciler.reconcile(reconciler_opts())
    refute_receive {:reconciler_import_event, _}

    assert {:ok, importing} = Content.get_video(video.id)
    assert importing.download_state == :importing
    assert Repo.get!(Oban.Job, job.id).state == "available"
  end

  test "recovers an importing video whose job disappeared" do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})
    missing_job_id = 9_000_000_000 + System.unique_integer([:positive])

    assert {:ok, _importing} =
             Content.begin_video_import(video, %{
               import_job_id: missing_job_id,
               import_manifest: %{"missing" => true}
             })

    assert :ok = Reconciler.reconcile(reconciler_opts())
    video_id = video.id
    assert_receive {:reconciler_import_event, {:video_import_failed, _, ^video_id, _}}

    assert {:ok, failed} = Content.get_video(video.id)
    assert failed.download_state == :import_failed
  end

  test "preserves downloaded finals and warns only when their cleanup journal remains" do
    {video, job} = importing_job("executing")

    assert {:ok, importing} = Content.get_video(video.id)

    assert {:ok, imported} =
             Content.mark_video_imported(importing, %{
               download_path: "/tmp/reconciled-#{job.id}.mkv",
               file_size: 4,
               download_quality: "720p",
               import_recovery: %{"mode" => "delete", "entries" => [%{"path" => "/tmp/marker"}]}
             })

    assert :ok = Reconciler.reconcile(reconciler_opts())

    channel_id = imported.channel_id
    video_id = imported.id

    assert_receive {:reconciler_import_event,
                    {:video_import_cleanup_warning, ^channel_id, ^video_id}}

    assert {:ok, fresh} = Content.get_video(video.id)
    assert fresh.download_state == :downloaded
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"
  end

  defp importing_job(state) do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})
    manifest = %{"state" => state}

    job =
      Repo.insert!(%Oban.Job{
        worker: "Ytdarr.ObanWorkers.VideoImporter",
        queue: "video_importer",
        state: state,
        args: %{"video_id" => video.id, "manifest" => manifest}
      })

    assert {:ok, _importing} =
             Content.begin_video_import(video, %{import_job_id: job.id, import_manifest: manifest})

    {video, job}
  end

  defp reconciler_opts do
    [
      repo: Repo,
      content: Content,
      imports: ReconcilerImports,
      video_import: ReconcilerVideoImport
    ]
  end

  defmodule ReconcilerImports do
    def broadcast(event) do
      send(self(), {:reconciler_import_event, event})
      :ok
    end
  end

  defmodule ReconcilerVideoImport do
    defmodule Manifest do
      def from_map(_map), do: {:ok, %{}}
    end

    def recover(_job_id, _manifest, :importing), do: {:ok, []}
  end
end
