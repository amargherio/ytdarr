defmodule Ytdarr.Settings.StartupLoader do
  @moduledoc """
  Task that runs at application startup to initialize settings from environment variables.

  This module handles the one-time loading of sensitive configuration from environment
  variables into the database. The rule is:
  - If a database value exists, it is used (environment variable is ignored)
  - If no database value exists, we check the environment variable and store it

  This ensures the database is the source of truth once configured, while still
  allowing initial configuration via environment variables.
  """

  use Task, restart: :transient

  alias Ytdarr.Env
  alias Ytdarr.Settings

  require Logger

  @doc """
  Starts the startup loader task.
  """
  def start_link(_arg) do
    Task.start_link(__MODULE__, :run, [])
  end

  @doc """
  Runs the startup initialization logic.
  """
  def run do
    Logger.info("[StartupLoader] Initializing settings from environment...")

    load_youtube_api_key()

    Logger.info("[StartupLoader] Settings initialization complete")
  end

  @doc """
  Loads the YouTube API key from environment into the database if not already set.

  The environment variable `YTDARR_YOUTUBE_API_KEY` is checked. If the database
  setting `youtube.primary_api_key` is empty/nil and the env var is present,
  the env var value is stored in the database.
  """
  def load_youtube_api_key do
    db_value = get_raw_setting_value("youtube.primary_api_key")
    env_value = Env.get("YTDARR_YOUTUBE_API_KEY")

    cond do
      # Database has a value - use it, ignore env
      not empty?(db_value) ->
        Logger.debug("[StartupLoader] YouTube API key already configured in database")
        :ok

      # No database value, but env has one - store it
      not empty?(env_value) ->
        Logger.info("[StartupLoader] Loading YouTube API key from environment variable")

        case Settings.put_setting("youtube.primary_api_key", env_value, "string") do
          {:ok, _} ->
            Logger.info("[StartupLoader] YouTube API key stored successfully")
            :ok

          {:error, reason} ->
            Logger.error("[StartupLoader] Failed to store YouTube API key: #{inspect(reason)}")
            {:error, reason}
        end

      # Neither has a value
      true ->
        Logger.warning(
          "[StartupLoader] No YouTube API key configured. " <>
            "Set YTDARR_YOUTUBE_API_KEY environment variable or configure in Settings."
        )

        :ok
    end
  end

  # Get the raw database value without any environment overrides
  defp get_raw_setting_value(key) do
    case Settings.get_app_setting_by_key(key) do
      {:ok, nil} -> nil
      {:ok, %{value: value}} -> unwrap_value(value)
      {:error, _} -> nil
    end
  end

  defp unwrap_value(%{"v" => v}), do: v
  defp unwrap_value(v), do: v

  defp empty?(nil), do: true
  defp empty?(""), do: true
  defp empty?(_), do: false
end
