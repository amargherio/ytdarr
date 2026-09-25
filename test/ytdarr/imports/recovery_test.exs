defmodule Ytdarr.Imports.RecoveryTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.Imports.Recovery
  alias __MODULE__.{RecoveryImports, RecoveryVideoImport}

  @empty_recovery %{"mode" => nil, "entries" => []}

  test "records no recovery work when rollback succeeds without entries" do
    {video, importing} = importing_video("ok_empty")

    assert {:ok, failed} = Recovery.recover_importing(importing, recovery_opts())
    assert failed.download_state == :import_failed
    assert failed.import_recovery == @empty_recovery

    assert_receive {:recovery_event, {:video_import_failed, _, video_id, _}}
    assert video_id == video.id
  end

  test "records no recovery work when rollback reports an empty failure journal" do
    {_video, importing} = importing_video("error_empty")

    assert {:ok, failed} = Recovery.recover_importing(importing, recovery_opts())
    assert failed.download_state == :import_failed
    assert failed.import_recovery == @empty_recovery

    assert {:ok, retried} =
             Content.begin_video_import(failed, %{
               import_job_id: System.unique_integer([:positive]),
               import_manifest: %{"source" => "retry"}
             })

    assert retried.download_state == :importing
  end

  test "retains actionable source recovery entries" do
    {_video, importing} = importing_video("error_entries")

    assert {:ok, failed} = Recovery.recover_importing(importing, recovery_opts())

    assert failed.import_recovery == %{
             "mode" => "restore",
             "entries" => [%{"path" => "/tmp/recovery-source"}]
           }
  end

  defp importing_video(outcome) do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})
    job_id = System.unique_integer([:positive])

    assert {:ok, importing} =
             Content.begin_video_import(video, %{
               import_job_id: job_id,
               import_manifest: %{"outcome" => outcome}
             })

    {video, importing}
  end

  defp recovery_opts do
    [content: Content, imports: RecoveryImports, video_import: RecoveryVideoImport]
  end

  defmodule RecoveryImports do
    def broadcast(event) do
      send(self(), {:recovery_event, event})
      :ok
    end
  end

  defmodule RecoveryVideoImport do
    defmodule Manifest do
      def from_map(manifest), do: {:ok, manifest}
    end

    def recover(_job_id, %{"outcome" => "ok_empty"}, :importing), do: {:ok, []}
    def recover(_job_id, %{"outcome" => "error_empty"}, :importing), do: {:error, []}

    def recover(_job_id, %{"outcome" => "error_entries"}, :importing),
      do: {:error, [%{"path" => "/tmp/recovery-source"}]}
  end
end
