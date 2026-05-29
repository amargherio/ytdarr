defmodule Ytdarr.Downloads.TrackerTest do
  use ExUnit.Case

  alias Ytdarr.Downloads.Tracker

  setup do
    reset_tracker()
    Phoenix.PubSub.subscribe(Ytdarr.PubSub, "downloads")
    flush_mailbox()

    on_exit(fn ->
      flush_mailbox()
      reset_tracker()
    end)

    :ok
  end

  describe "track_start/2 and get_progress/1" do
    test "stores initial progress state for a download" do
      job_id = unique_id()
      video_id = unique_id()

      assert :ok = Tracker.track_start(job_id, video_id)

      assert %{
               pct: nil,
               speed: nil,
               eta: nil,
               started_at: %DateTime{},
               updated_at: %DateTime{}
             } = Tracker.get_progress(video_id)
    end
  end

  describe "update_progress/3" do
    test "stores progress updates for an active download" do
      job_id = unique_id()
      video_id = unique_id()

      Tracker.track_start(job_id, video_id)
      Tracker.update_progress(job_id, video_id, %{pct: 45.2, speed: "12.5MiB/s", eta: "00:42"})

      assert %{
               pct: 45.2,
               speed: "12.5MiB/s",
               eta: "00:42",
               started_at: %DateTime{},
               updated_at: %DateTime{}
             } = Tracker.get_progress(video_id)
    end

    test "returns the most recently updated progress when a video has multiple jobs" do
      video_id = unique_id()
      first_job_id = unique_id()
      second_job_id = unique_id()

      Tracker.track_start(first_job_id, video_id)
      Tracker.track_start(second_job_id, video_id)

      Tracker.update_progress(first_job_id, video_id, %{
        pct: 25.0,
        speed: "1.0MiB/s",
        eta: "00:30"
      })

      Process.sleep(10)

      Tracker.update_progress(second_job_id, video_id, %{
        pct: 80.0,
        speed: "3.0MiB/s",
        eta: "00:05"
      })

      assert %{pct: 80.0, speed: "3.0MiB/s", eta: "00:05"} = Tracker.get_progress(video_id)
    end

    test "overwrites prior progress values for the same job and video" do
      job_id = unique_id()
      video_id = unique_id()

      Tracker.track_start(job_id, video_id)
      Tracker.update_progress(job_id, video_id, %{pct: 10.0, speed: "1.0MiB/s", eta: "00:20"})
      Process.sleep(10)
      Tracker.update_progress(job_id, video_id, %{pct: 55.5, speed: "2.5MiB/s", eta: "00:08"})

      assert %{pct: 55.5, speed: "2.5MiB/s", eta: "00:08"} = Tracker.get_progress(video_id)
    end

    test "broadcasts the first update immediately" do
      job_id = unique_id()
      video_id = unique_id()
      progress = %{pct: 10.0, speed: "1.0MiB/s", eta: "00:10"}

      Tracker.track_start(job_id, video_id)
      Tracker.update_progress(job_id, video_id, progress)

      assert_receive {:download_progress, ^job_id, ^video_id, ^progress}, 200
    end

    test "throttles rapid updates until one second has passed" do
      job_id = unique_id()
      video_id = unique_id()

      Tracker.track_start(job_id, video_id)
      Tracker.update_progress(job_id, video_id, %{pct: 10.0, speed: "1.0MiB/s", eta: "00:10"})

      assert_receive {:download_progress, ^job_id, ^video_id, %{pct: 10.0}}, 200

      Tracker.update_progress(job_id, video_id, %{pct: 20.0, speed: "2.0MiB/s", eta: "00:09"})
      refute_receive {:download_progress, ^job_id, ^video_id, _}, 150

      Process.sleep(1_100)
      Tracker.update_progress(job_id, video_id, %{pct: 30.0, speed: "3.0MiB/s", eta: "00:08"})

      assert_receive {:download_progress, ^job_id, ^video_id,
                      %{pct: 30.0, speed: "3.0MiB/s", eta: "00:08"}},
                     200
    end
  end

  describe "track_complete/2" do
    test "removes tracked progress when a download completes" do
      job_id = unique_id()
      video_id = unique_id()

      Tracker.track_start(job_id, video_id)
      Tracker.track_complete(job_id, video_id)

      assert Tracker.get_progress(video_id) == nil
    end
  end

  describe "list_active/0" do
    test "returns all currently tracked downloads" do
      first = {unique_id(), unique_id()}
      second = {unique_id(), unique_id()}

      Tracker.track_start(elem(first, 0), elem(first, 1))
      Tracker.track_start(elem(second, 0), elem(second, 1))

      active = Tracker.list_active() |> Map.new()

      assert Map.keys(active) |> Enum.sort() == Enum.sort([elem(first, 1), elem(second, 1)])
      assert %{pct: nil, speed: nil, eta: nil} = active[elem(first, 1)]
      assert %{pct: nil, speed: nil, eta: nil} = active[elem(second, 1)]
    end

    test "removes completed downloads from the active list" do
      first_job_id = unique_id()
      first_video_id = unique_id()
      second_job_id = unique_id()
      second_video_id = unique_id()

      Tracker.track_start(first_job_id, first_video_id)
      Tracker.track_start(second_job_id, second_video_id)
      Tracker.track_complete(first_job_id, first_video_id)

      assert [{^second_video_id, %{pct: nil, speed: nil, eta: nil}}] = Tracker.list_active()
    end

    test "tracks multiple downloads independently" do
      first_job_id = unique_id()
      first_video_id = unique_id()
      second_job_id = unique_id()
      second_video_id = unique_id()

      Tracker.track_start(first_job_id, first_video_id)
      Tracker.track_start(second_job_id, second_video_id)

      Tracker.update_progress(first_job_id, first_video_id, %{
        pct: 12.5,
        speed: "1.2MiB/s",
        eta: "00:40"
      })

      Tracker.update_progress(second_job_id, second_video_id, %{
        pct: 87.0,
        speed: "5.5MiB/s",
        eta: "00:03"
      })

      assert %{pct: 12.5, speed: "1.2MiB/s", eta: "00:40"} = Tracker.get_progress(first_video_id)
      assert %{pct: 87.0, speed: "5.5MiB/s", eta: "00:03"} = Tracker.get_progress(second_video_id)
    end
  end

  defp reset_tracker do
    :sys.replace_state(Tracker, fn _state -> %{} end)
  end

  defp unique_id do
    System.unique_integer([:positive])
  end

  defp flush_mailbox do
    receive do
      _message -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
