defmodule YtdarrWeb.QueueLiveTest do
  use YtdarrWeb.ConnCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  alias Ytdarr.ObanWorkers.VideoDownloader
  alias Ytdarr.Repo

  describe "queue page" do
    test "renders empty state when no downloads", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")

      assert has_element?(view, "#queue-summary")
      assert has_element?(view, "#queue-active")
      assert has_element?(view, "#queue-active-empty")
      assert has_element?(view, "#queue-pending")
      assert has_element?(view, "#queue-pending-empty")
    end

    test "renders queue status summary cards", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")

      assert has_element?(view, "#queue-summary")
      assert has_element?(view, "#queue-summary div", "Active downloads")
      assert has_element?(view, "#queue-summary div", "Pending jobs")
      assert has_element?(view, "#queue-summary div", "Worker slots")
    end

    test "renders queue status and pending downloads", %{conn: conn} do
      %{channel: channel, video: video, job: job} = enqueue_download_fixture()

      {:ok, view, _html} = live(conn, ~p"/queue")

      assert has_element?(view, "#queue-summary")
      assert has_element?(view, "#queue-active")
      assert has_element?(view, "#queue-pending")
      assert has_element?(view, "#pending-download-#{job.id}")
      assert has_element?(view, "#pending-download-#{job.id}", video.title)
      assert has_element?(view, "#pending-download-#{job.id}", channel.name)
    end

    test "shows queue position for pending downloads", %{conn: conn} do
      %{job: first_job} = enqueue_download_fixture()
      %{job: second_job} = enqueue_download_fixture()

      {:ok, view, _html} = live(conn, ~p"/queue")

      assert has_element?(view, "#pending-download-#{first_job.id} > div:first-child", "1")
      assert has_element?(view, "#pending-download-#{second_job.id} > div:first-child", "2")
    end

    test "refresh button reloads the queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      %{video: video, job: job} = enqueue_download_fixture()

      assert has_element?(view, "#queue-refresh")
      assert has_element?(view, "#queue-pending-empty")
      refute has_element?(view, "#pending-download-#{job.id}")

      view
      |> element("#queue-refresh")
      |> render_click()

      assert has_element?(view, "#pending-download-#{job.id}")
      assert has_element?(view, "#pending-download-#{job.id}", video.title)
      refute has_element?(view, "#queue-pending-empty")
    end

    test "pubsub download_queued refreshes the queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      %{channel: channel, video: video, job: job} = enqueue_download_fixture()

      assert has_element?(view, "#queue-pending-empty")
      refute has_element?(view, "#pending-download-#{job.id}")

      Phoenix.PubSub.broadcast(
        Ytdarr.PubSub,
        "downloads",
        {:download_queued, video.id, %{title: video.title, channel_name: channel.name}}
      )

      assert has_element?(view, "#pending-download-#{job.id}")
      assert has_element?(view, "#pending-download-#{job.id}", video.title)
      refute has_element?(view, "#queue-pending-empty")
    end

    test "highlights the queue navigation item", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")

      assert has_element?(
               view,
               "a[href='/queue'][class*='bg-primary/10'][class*='text-primary'][class*='font-semibold']",
               "Queue"
             )
    end

    test "pubsub download_progress renders progress for an active download", %{conn: conn} do
      %{job: job, video: video} = enqueue_active_download_fixture()

      {:ok, view, _html} = live(conn, ~p"/queue")

      assert has_element?(view, "#active-download-#{job.id}", video.title)

      Phoenix.PubSub.broadcast(
        Ytdarr.PubSub,
        "downloads",
        {:download_progress, job.id, video.id, %{pct: 12.5, speed: "5MiB/s", eta: "00:30"}}
      )

      assert has_element?(view, "#active-download-#{job.id}", "12.5%")
      assert has_element?(view, "#active-download-#{job.id}", "5MiB/s")
      assert has_element?(view, "#active-download-#{job.id}", "ETA 00:30")
    end

    test "pubsub download_started reloads the queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      %{job: job, video: video} = enqueue_download_fixture()

      refute has_element?(view, "#pending-download-#{job.id}")

      Phoenix.PubSub.broadcast(
        Ytdarr.PubSub,
        "downloads",
        {:download_started, job.id, video.id, %{title: video.title, channel_name: "x"}}
      )

      assert has_element?(view, "#pending-download-#{job.id}")
    end

    test "pubsub download_failed reloads the queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      %{job: job, video: video} = enqueue_download_fixture()

      Phoenix.PubSub.broadcast(
        Ytdarr.PubSub,
        "downloads",
        {:download_failed, job.id, video.id, :reason}
      )

      assert has_element?(view, "#pending-download-#{job.id}")
    end

    test "pubsub download_completed reloads the queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      %{job: job} = enqueue_download_fixture()

      Phoenix.PubSub.broadcast(
        Ytdarr.PubSub,
        "downloads",
        {:download_completed, job.id, 999}
      )

      assert has_element?(view, "#pending-download-#{job.id}")
    end

    test "unknown pubsub messages are ignored gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      Phoenix.PubSub.broadcast(Ytdarr.PubSub, "downloads", :some_unknown_message)
      assert is_binary(render(view))
    end

    test ":poll message reloads the queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/queue")
      %{job: job} = enqueue_download_fixture()

      refute has_element?(view, "#pending-download-#{job.id}")
      send(view.pid, :poll)
      assert has_element?(view, "#pending-download-#{job.id}")
    end
  end

  defp enqueue_download_fixture do
    unique_id = System.unique_integer([:positive])

    channel =
      channel_fixture(%{
        name: "Queue Channel #{unique_id}",
        is_monitored: true
      })

    video =
      video_fixture(%{
        channel_id: channel.id,
        title: "Queued Video #{unique_id}"
      })

    {:ok, job} =
      VideoDownloader.new(%{"video_id" => video.id, "channel_id" => channel.id})
      |> Oban.insert()

    %{channel: channel, video: video, job: job}
  end

  defp enqueue_active_download_fixture do
    %{channel: channel, video: video, job: job} = enqueue_download_fixture()

    job =
      job
      |> Ecto.Changeset.change(state: "executing", attempted_at: DateTime.utc_now())
      |> Repo.update!()

    %{channel: channel, video: video, job: job}
  end
end
