defmodule Ytdarr.Media.Ffprobe do
  @moduledoc """
  Runs ffprobe without a shell and returns the first video stream's height.
  """

  @default_timeout_ms 15_000
  @max_output_bytes 1_048_576
  @ffprobe_args [
    "-v",
    "error",
    "-select_streams",
    "v:0",
    "-show_entries",
    "stream=height",
    "-of",
    "json"
  ]

  @type result :: %{height: integer() | nil, quality: String.t() | nil}
  @type error_reason ::
          :ffprobe_unavailable
          | :ffprobe_timeout
          | :ffprobe_output_too_large
          | :ffprobe_malformed_output
          | :ffprobe_failed
          | :no_video_stream

  @doc "Probes the first video stream at `path`."
  @spec probe(Path.t()) :: {:ok, result()} | {:error, error_reason()}
  @spec probe(Path.t(), non_neg_integer()) :: {:ok, result()} | {:error, error_reason()}
  def probe(path, timeout_ms \\ @default_timeout_ms)

  def probe(path, timeout_ms)
      when is_binary(path) and is_integer(timeout_ms) and timeout_ms >= 0 do
    with {:ok, executable} <- resolve_executable(),
         {:ok, port} <- open_port(executable, path) do
      deadline = System.monotonic_time(:millisecond) + timeout_ms
      receive_output(port, deadline, [], 0)
    end
  end

  def probe(_path, _timeout_ms), do: {:error, :ffprobe_failed}

  defp resolve_executable do
    case Application.get_env(:ytdarr, :ffprobe_path) do
      nil ->
        case System.find_executable("ffprobe") do
          nil -> {:error, :ffprobe_unavailable}
          path -> {:ok, path}
        end

      path when is_binary(path) and byte_size(path) > 0 ->
        if executable_file?(path), do: {:ok, path}, else: {:error, :ffprobe_unavailable}

      _configured_path ->
        {:error, :ffprobe_unavailable}
    end
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  defp open_port(executable, path) do
    try do
      {:ok,
       Port.open({:spawn_executable, executable}, [
         :binary,
         :exit_status,
         :stderr_to_stdout,
         args: @ffprobe_args ++ [path]
       ])}
    rescue
      _exception -> {:error, :ffprobe_failed}
    catch
      _kind, _reason -> {:error, :ffprobe_failed}
    end
  end

  defp receive_output(port, deadline, output, output_size) do
    receive do
      {^port, {:data, data}} when is_binary(data) ->
        size = output_size + byte_size(data)

        if size > @max_output_bytes do
          close_port(port)
          {:error, :ffprobe_output_too_large}
        else
          receive_output(port, deadline, [data | output], size)
        end

      {^port, {:exit_status, 0}} ->
        output
        |> Enum.reverse()
        |> IO.iodata_to_binary()
        |> decode_output()

      {^port, {:exit_status, _status}} ->
        {:error, :ffprobe_failed}

      {^port, :closed} ->
        {:error, :ffprobe_failed}
    after
      remaining_timeout(deadline) ->
        close_port(port)
        {:error, :ffprobe_timeout}
    end
  end

  defp remaining_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  defp decode_output(output) do
    case Jason.decode(output) do
      {:ok, %{"streams" => []}} ->
        {:error, :no_video_stream}

      {:ok, %{"streams" => [stream | _]}} when is_map(stream) ->
        stream_result(stream)

      _ ->
        {:error, :ffprobe_malformed_output}
    end
  end

  defp stream_result(%{"height" => height}) when is_integer(height) and height > 0 do
    {:ok, %{height: height, quality: "#{height}p"}}
  end

  defp stream_result(%{"height" => height}) when is_integer(height) do
    {:ok, %{height: height, quality: nil}}
  end

  defp stream_result(%{"height" => nil}), do: {:ok, %{height: nil, quality: nil}}
  defp stream_result(stream) when is_map(stream), do: {:ok, %{height: nil, quality: nil}}

  defp close_port(port) do
    os_pid = port_os_pid(port)
    close_port_handle(port)
    terminate_os_process(os_pid)
  end

  defp port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> os_pid
      nil -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp close_port_handle(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp terminate_os_process(nil), do: :ok

  defp terminate_os_process(os_pid) do
    case System.find_executable("kill") do
      nil ->
        :ok

      executable ->
        _ = System.cmd(executable, ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
        :ok
    end
  rescue
    _exception -> :ok
  end
end
