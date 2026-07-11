defmodule Ytdarr.Env do
  @moduledoc false

  def get(name) when is_binary(name) do
    file_name = "#{name}_FILE"

    case {System.fetch_env(name), System.fetch_env(file_name)} do
      {{:ok, _value}, {:ok, _path}} ->
        raise ArgumentError, "set either #{name} or #{file_name}, not both"

      {{:ok, value}, :error} ->
        normalize(value)

      {:error, {:ok, path}} ->
        read_file!(name, file_name, path)

      {:error, :error} ->
        nil
    end
  end

  def fetch!(name) when is_binary(name) do
    get(name) ||
      raise ArgumentError, "missing environment variable #{name} or #{name}_FILE"
  end

  defp read_file!(name, file_name, path) do
    path =
      normalize(path) ||
        raise ArgumentError, "environment variable #{file_name} must contain a file path"

    case File.read(path) do
      {:ok, value} ->
        normalize(value) || raise ArgumentError, "secret file for #{name} is empty"

      {:error, reason} ->
        raise ArgumentError,
              "could not read secret file for #{name}: #{:file.format_error(reason)}"
    end
  end

  defp normalize(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end
end
