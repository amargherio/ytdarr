defmodule Ytdarr.NativeReleaseTest do
  use ExUnit.Case, async: true

  @validator Path.expand("../../deploy/scripts/validate-native.sh", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "native-release-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {os, 0} =
      System.cmd("bash", [
        "-c",
        "source /etc/os-release; printf '%s\\n%s' \"$ID\" \"${VERSION_ID:-rolling}\""
      ])

    [id, version] = String.split(os, "\n")
    {glibc, 0} = System.cmd("getconf", ["GNU_LIBC_VERSION"])

    metadata = %{
      "format" => "1",
      "version" => "1.2.3",
      "os_id" => id,
      "os_version" => version,
      "arch" => "x86_64",
      "glibc_version" => glibc |> String.trim() |> String.replace_prefix("glibc ", ""),
      "otp_version" => "29.0",
      "elixir_version" => "1.20.4",
      "source_revision" => String.duplicate("a", 40),
      "build_date" => "2026-10-16T00:00:00Z"
    }

    %{root: root, metadata: metadata}
  end

  test "accepts a checksum-bound release for the current host", context do
    archive = archive(context.root, context.metadata)
    assert {_output, 0} = validate(archive)
  end

  test "rejects changed archive bytes and checksums naming another file", context do
    archive = archive(context.root, context.metadata)
    checksum = File.read!(archive <> ".sha256")
    File.write!(archive <> ".sha256", String.replace(checksum, "release.tar.gz", "other.tar.gz"))
    assert {message, 1} = validate(archive)
    assert message =~ "checksum names a different archive"

    File.write!(archive <> ".sha256", checksum)
    File.write!(archive, "tampered", [:append])
    assert {message, 1} = validate(archive)
    assert message =~ "archive checksum mismatch"
  end

  test "rejects incompatible OS, architecture, version, and glibc", context do
    for {key, value, reason} <- [
          {"os_id", "unrelated-linux", "archive targets"},
          {"arch", "aarch64", "unsupported archive architecture"},
          {"version", "9.9.9", "does not match requested version"},
          {"glibc_version", "999.0", "archive needs glibc"}
        ] do
      archive = archive(context.root, Map.put(context.metadata, key, value))
      assert {message, 1} = validate(archive)
      assert message =~ reason
    end
  end

  test "rejects missing metadata and never evaluates metadata as shell code", context do
    archive = archive(context.root, Map.delete(context.metadata, "format"))
    assert {message, 1} = validate(archive)
    assert message =~ "missing metadata field: format"

    marker = Path.join(context.root, "executed")

    archive =
      archive(context.root, Map.put(context.metadata, "source_revision", "$(touch #{marker})"))

    assert {_message, 1} = validate(archive)
    refute File.exists?(marker)
  end

  defp archive(root, metadata) do
    File.write!(
      Path.join(root, "release-target"),
      Enum.map_join(metadata, "\n", fn {key, value} -> "#{key}=#{value}" end) <> "\n"
    )

    archive = Path.join(root, "release.tar.gz")
    {_, 0} = System.cmd("tar", ["-czf", archive, "-C", root, "release-target"])
    digest = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)
    File.write!(archive <> ".sha256", "#{digest}  release.tar.gz\n")
    archive
  end

  defp validate(archive) do
    System.cmd("bash", [@validator, archive, archive <> ".sha256", "1.2.3"],
      stderr_to_stdout: true
    )
  end
end
