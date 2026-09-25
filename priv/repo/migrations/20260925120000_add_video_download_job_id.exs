defmodule Ytdarr.Repo.Migrations.AddVideoDownloadJobId do
  @moduledoc """
  Persists the exact Oban downloader job currently associated with a video.
  """

  use Ecto.Migration

  def up do
    alter table(:videos) do
      add :download_job_id, :bigint
    end

    # Preserve ownership for downloads queued before this column existed.
    execute("""
    UPDATE videos
    SET download_job_id = (
      SELECT job.id FROM oban_jobs AS job
      WHERE job.worker = 'Ytdarr.ObanWorkers.VideoDownloader'
        AND job.queue = 'video_downloader'
        AND job.state IN ('available', 'scheduled', 'executing', 'retryable', 'suspended')
        AND json_valid(job.args)
        AND json_type(job.args, '$.video_id') = 'integer'
        AND json_extract(job.args, '$.video_id') = videos.id
      ORDER BY job.id DESC LIMIT 1
    )
    WHERE download_state IN ('queued', 'downloading')
    """)

    # An orphaned queue state has no job left to execute or cancel.
    execute("""
    UPDATE videos SET download_state = 'available', is_downloaded = 0
    WHERE download_state IN ('queued', 'downloading') AND download_job_id IS NULL
    """)

    create unique_index(:videos, [:download_job_id], name: "videos_unique_download_job_id_index")
  end

  def down do
    drop_if_exists unique_index(:videos, [:download_job_id],
                     name: "videos_unique_download_job_id_index"
                   )

    alter table(:videos) do
      remove :download_job_id
    end
  end
end
