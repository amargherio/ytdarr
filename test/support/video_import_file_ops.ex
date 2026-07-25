defmodule Ytdarr.TestSupport.VideoImportFileOps do
  @moduledoc false

  @behaviour Ytdarr.Media.VideoImport.FileOps

  @type operation :: :copy | :link | :quarantine | :restore | :remove

  def start_link(opts \\ []) do
    fail_after = Keyword.get(opts, :fail_after, %{})
    fail_before = Keyword.get(opts, :fail_before, %{})

    Agent.start_link(fn ->
      %{fail_after: fail_after, fail_before: fail_before, counts: %{}, before_counts: %{}}
    end)
  end

  def calls(agent), do: Agent.get(agent, & &1.counts)

  @impl true
  def lstat(_agent, path), do: File.lstat(path, time: :posix)

  @impl true
  def stat(_agent, path, options), do: File.stat(path, options)

  @impl true
  def list(_agent, path), do: File.ls(path)

  @impl true
  def mkdir(_agent, path), do: File.mkdir(path)

  @impl true
  def create_exclusive(_agent, path, contents),
    do: File.write(path, contents, [:exclusive, :binary])

  @impl true
  def copy(agent, source, destination) do
    File.cp(source, destination)
    |> fail_after(agent, :copy)
  end

  @impl true
  def hard_link(agent, source, destination) do
    File.ln(source, destination)
    |> fail_after(agent, :link)
  end

  @impl true
  def rename(agent, source, destination) do
    operation = if quarantine_path?(destination), do: :quarantine, else: :restore

    File.rename(source, destination)
    |> fail_after(agent, operation)
  end

  @impl true
  def remove(agent, path) do
    case fail_before(agent, :remove) do
      :ok -> File.rm(path) |> fail_after(agent, :remove)
      error -> error
    end
  end

  @impl true
  def remove_dir(_agent, path), do: File.rmdir(path)

  @impl true
  def touch(_agent, path, time), do: File.touch(path, time)

  defp quarantine_path?(path) do
    path
    |> Path.dirname()
    |> Path.basename()
    |> String.starts_with?(".ytdarr-import-")
  end

  defp fail_before(agent, operation) do
    Agent.get_and_update(agent, fn state ->
      count = Map.get(state.before_counts, operation, 0) + 1
      next_state = %{state | before_counts: Map.put(state.before_counts, operation, count)}

      case Map.get(state.fail_before, operation) do
        ^count -> {{:error, {:injected_failure, operation, count}}, next_state}
        _ -> {:ok, next_state}
      end
    end)
  end

  defp fail_after({:ok, _value}, agent, operation), do: fail_after(:ok, agent, operation)

  defp fail_after(:ok, agent, operation) do
    Agent.get_and_update(agent, fn state ->
      count = Map.get(state.counts, operation, 0) + 1
      next_state = %{state | counts: Map.put(state.counts, operation, count)}

      case Map.get(state.fail_after, operation) do
        ^count -> {{:error, {:injected_failure, operation, count}}, next_state}
        _ -> {:ok, next_state}
      end
    end)
  end

  defp fail_after(result, _agent, _operation), do: result
end
