defmodule Ytdarr.Imports do
  @moduledoc false

  @pubsub Ytdarr.PubSub
  @topic "video_imports"

  @type event ::
          {:video_import_started, channel_id :: integer(), video_id :: integer()}
          | {:video_import_completed, channel_id :: integer(), video_id :: integer()}
          | {:video_import_failed, channel_id :: integer(), video_id :: integer(),
             safe_message :: String.t()}
          | {:video_import_cleanup_warning, channel_id :: integer(), video_id :: integer()}
          | {:video_import_recovery_updated, channel_id :: integer(), video_id :: integer()}

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @spec broadcast(event()) :: :ok
  def broadcast(event), do: Phoenix.PubSub.broadcast(@pubsub, @topic, event)

  @spec broadcast_from(event()) :: :ok
  def broadcast_from(event), do: Phoenix.PubSub.broadcast_from(@pubsub, self(), @topic, event)

  @spec queue_concurrency() :: pos_integer() | nil
  def queue_concurrency do
    runtime_limit =
      case Oban.config() do
        %{queues: queues} -> queue_limit(Keyword.get(queues, :video_importer))
        _ -> nil
      end

    runtime_limit || configured_queue_limit(:video_importer)
  end

  defp configured_queue_limit(queue) do
    :ytdarr
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Keyword.get(queue)
    |> queue_limit()
  end

  defp queue_limit(nil), do: nil
  defp queue_limit(limit) when is_integer(limit), do: limit
  defp queue_limit(config) when is_list(config), do: Keyword.get(config, :limit)
  defp queue_limit(%{limit: limit}), do: limit
  defp queue_limit(_config), do: nil
end
