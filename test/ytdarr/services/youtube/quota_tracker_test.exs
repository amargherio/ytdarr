defmodule Ytdarr.Services.YouTube.QuotaTrackerTest do
  use Ytdarr.DataCase, async: false

  alias Ytdarr.Services.YouTube.QuotaTracker
  alias Ytdarr.Settings

  @setting_keys [
    "youtube.daily_quota_limit",
    "youtube.quota_used_today",
    "youtube.quota_reset_date"
  ]

  setup do
    original_settings = Map.new(@setting_keys, &{&1, Settings.get_setting_value(&1)})
    assert :ok = QuotaTracker.reset()

    on_exit(fn ->
      Enum.each(@setting_keys, fn key ->
        case Map.fetch!(original_settings, key) do
          nil -> delete_setting(key)
          value -> Settings.put_setting(key, value)
        end
      end)

      QuotaTracker.reset()
    end)

    :ok
  end

  test "starts under the application supervisor" do
    assert pid = Process.whereis(QuotaTracker)
    assert Process.alive?(pid)
  end

  test "records usage and reports remaining quota" do
    assert :ok = QuotaTracker.record_usage(:read, 5)
    assert :ok = QuotaTracker.record_usage(:search)

    usage = QuotaTracker.get_usage()

    assert usage.used == 105
    assert usage.remaining == usage.limit - 105
    assert usage.percentage == Float.round(105 / usage.limit * 100, 2)
  end

  test "checks whether an operation fits within the remaining quota" do
    usage = QuotaTracker.get_usage()
    upload_cost = QuotaTracker.get_cost(:upload)

    assert QuotaTracker.can_afford?(:upload, div(usage.limit, upload_cost))
    refute QuotaTracker.can_afford?(:upload, div(usage.limit, upload_cost) + 1)
  end

  test "resets quota when the scheduled rollover check sees a stale day" do
    utc_now = DateTime.utc_now()
    pt_offset_hours = -8

    pt_today =
      utc_now
      |> DateTime.add(pt_offset_hours * 3600, :second)
      |> DateTime.to_date()

    stale_date = Date.add(pt_today, -1)

    :sys.replace_state(QuotaTracker, fn state ->
      %{state | used: 250, reset_date: stale_date}
    end)

    send(Process.whereis(QuotaTracker), :check_reset)
    Process.sleep(25)

    usage = QuotaTracker.get_usage()

    assert usage.used == 0
    assert usage.remaining == usage.limit
    refute :sys.get_state(QuotaTracker).reset_date == stale_date
  end

  test "record_usage returns :warning past 80% and :critical past 95%" do
    usage = QuotaTracker.get_usage()
    eighty_pct = trunc(usage.limit * 0.81)
    assert {:warning, _} = QuotaTracker.record_usage(:read, eighty_pct)

    QuotaTracker.reset()
    ninety_six_pct = trunc(usage.limit * 0.96)
    assert {:critical, _} = QuotaTracker.record_usage(:read, ninety_six_pct)
  end

  test "get_cost returns the configured cost per operation" do
    assert QuotaTracker.get_cost(:read) == 1
    assert QuotaTracker.get_cost(:search) == 100
    assert QuotaTracker.get_cost(:write) == 50
    assert QuotaTracker.get_cost(:upload) == 1_600
    assert QuotaTracker.get_cost(:thumbnail) == 50
    # Unknown operations fall back to 1
    assert QuotaTracker.get_cost(:unknown) == 1
  end

  test "estimate_batch_cost handles each operation shape" do
    # :channel_sync = ceil(count/50) + count + count*2
    assert QuotaTracker.estimate_batch_cost(:channel_sync, 10) == 1 + 10 + 20
    # :playlist_sync = count*2 + count*2
    assert QuotaTracker.estimate_batch_cost(:playlist_sync, 5) == 10 + 10
    # :search uses the per-call search cost
    assert QuotaTracker.estimate_batch_cost(:search, 3) == 300
    # Unknown operation falls back to read cost (1) × count
    assert QuotaTracker.estimate_batch_cost(:unknown_op, 7) == 7
  end

  test "reset/0 clears used and refreshes reset_date" do
    QuotaTracker.record_usage(:search)
    assert QuotaTracker.get_usage().used > 0
    assert :ok = QuotaTracker.reset()
    assert QuotaTracker.get_usage().used == 0
  end

  test "get_usage exposes the configured limit and next reset time" do
    usage = QuotaTracker.get_usage()
    assert usage.limit > 0
    assert %DateTime{} = usage.reset_at
  end

  defp delete_setting(key) do
    case Settings.delete_setting(key) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, _} -> :ok
    end
  end
end
