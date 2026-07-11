defmodule Ytdarr.EnvTest do
  use ExUnit.Case, async: false

  alias Ytdarr.Env

  @name "YTDARR_TEST_SECRET"
  @file_name "#{@name}_FILE"

  setup do
    System.delete_env(@name)
    System.delete_env(@file_name)

    on_exit(fn ->
      System.delete_env(@name)
      System.delete_env(@file_name)
    end)
  end

  test "returns a trimmed direct value" do
    System.put_env(@name, "  direct-secret  ")

    assert Env.get(@name) == "direct-secret"
  end

  test "reads and trims a secret file" do
    path = secret_file("  file-secret\n")
    System.put_env(@file_name, path)

    assert Env.get(@name) == "file-secret"
  end

  test "rejects direct and file values together" do
    System.put_env(@name, "direct-secret")
    System.put_env(@file_name, secret_file("file-secret"))

    assert_raise ArgumentError, ~r/set either .* not both/, fn -> Env.get(@name) end
  end

  test "rejects an empty secret file" do
    System.put_env(@file_name, secret_file(" \n"))

    assert_raise ArgumentError, ~r/secret file .* is empty/, fn -> Env.get(@name) end
  end

  test "returns nil when an optional value is absent or blank" do
    assert Env.get(@name) == nil

    System.put_env(@name, "  ")
    assert Env.get(@name) == nil
  end

  test "raises when a required value is absent" do
    assert_raise ArgumentError, ~r/missing environment variable/, fn -> Env.fetch!(@name) end
  end

  defp secret_file(contents) do
    path = Path.join(System.tmp_dir!(), "ytdarr-secret-#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
