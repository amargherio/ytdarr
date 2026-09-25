defmodule Ytdarr.Media.FfprobeTest do
  use ExUnit.Case, async: false

  alias Ytdarr.Media.Ffprobe

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ytdarr-ffprobe-#{System.unique_integer([:positive])}"
      )

    executable = Path.join(root, "ffprobe")
    original_path = Application.fetch_env(:ytdarr, :ffprobe_path)

    File.mkdir_p!(root)

    on_exit(fn ->
      restore_ffprobe_path(original_path)
      File.rm_rf!(root)
    end)

    {:ok, root: root, executable: executable}
  end

  test "returns a positive height and quality from the first video stream", %{
    root: root,
    executable: executable
  } do
    args_path = Path.join(root, "ffprobe-args")

    install_ffprobe(
      executable,
      "printf '%s\\n' \"$@\" > '#{args_path}'\nprintf '%s' '{\"streams\":[{\"height\":1080}]}'"
    )

    assert {:ok, %{height: 1080, quality: "1080p"}} = Ffprobe.probe("/media/legacy.mkv")

    assert File.read!(args_path) ==
             "-v\nerror\n-select_streams\nv:0\n-show_entries\nstream=height\n-of\njson\n/media/legacy.mkv\n"
  end

  test "returns a nil quality when ffprobe reports no stream height", %{executable: executable} do
    install_ffprobe(executable, "printf '%s' '{\"streams\":[{}]}'")

    assert {:ok, %{height: nil, quality: nil}} = Ffprobe.probe("/media/legacy.mkv")
  end

  test "reports a missing video stream", %{executable: executable} do
    install_ffprobe(executable, "printf '%s' '{\"streams\":[]}'")

    assert {:error, :no_video_stream} = Ffprobe.probe("/media/audio-only.mka")
  end

  test "reports malformed JSON output", %{executable: executable} do
    install_ffprobe(executable, "printf '%s' 'this is not json'")

    assert {:error, :ffprobe_malformed_output} = Ffprobe.probe("/media/legacy.mkv")
  end

  test "reports failed ffprobe processes", %{executable: executable} do
    install_ffprobe(executable, "printf '%s' '{\"streams\":[{\"height\":1080}]}'; exit 1")

    assert {:error, :ffprobe_failed} = Ffprobe.probe("/media/legacy.mkv")
  end

  test "caps ffprobe output at one mebibyte", %{executable: executable} do
    install_ffprobe(executable, "head -c 1048577 /dev/zero")

    assert {:error, :ffprobe_output_too_large} = Ffprobe.probe("/media/legacy.mkv")
  end

  test "accepts JSON output exactly at the one mebibyte limit", %{executable: executable} do
    install_ffprobe(
      executable,
      "head -c 1048562 /dev/zero | tr '\\000' ' '\nprintf '%s' '{\"streams\":[]}'"
    )

    assert {:error, :no_video_stream} = Ffprobe.probe("/media/audio-only.mka")
  end

  test "reports an unavailable configured executable", %{root: root} do
    Application.put_env(:ytdarr, :ffprobe_path, Path.join(root, "missing-ffprobe"))

    assert {:error, :ffprobe_unavailable} = Ffprobe.probe("/media/legacy.mkv")
  end

  test "closes timed-out ffprobe ports", %{root: root, executable: executable} do
    pid_path = Path.join(root, "ffprobe.pid")

    install_ffprobe(
      executable,
      "echo $$ > '#{pid_path}'\nwhile :; do :; done"
    )

    assert {:error, :ffprobe_timeout} = Ffprobe.probe("/media/legacy.mkv", 25)
    assert File.exists?(pid_path)

    pid = pid_path |> File.read!() |> String.trim() |> String.to_integer()
    refute_eventually(fn -> File.exists?("/proc/#{pid}") end)
  end

  defp install_ffprobe(path, body) do
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o755)
    Application.put_env(:ytdarr, :ffprobe_path, path)
  end

  defp restore_ffprobe_path({:ok, path}), do: Application.put_env(:ytdarr, :ffprobe_path, path)
  defp restore_ffprobe_path(:error), do: Application.delete_env(:ytdarr, :ffprobe_path)

  defp refute_eventually(predicate, attempts \\ 100)

  defp refute_eventually(predicate, 0), do: refute(predicate.())

  defp refute_eventually(predicate, attempts) do
    if predicate.() do
      Process.sleep(5)
      refute_eventually(predicate, attempts - 1)
    else
      :ok
    end
  end
end
