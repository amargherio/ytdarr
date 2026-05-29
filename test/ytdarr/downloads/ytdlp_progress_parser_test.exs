defmodule Ytdarr.Downloads.YtdlpProgressParserTest do
  use ExUnit.Case, async: true

  alias Ytdarr.Downloads.YtdlpProgressParser

  describe "parse_line/1" do
    test "parses progress template lines" do
      assert {:progress, %{pct: 45.2, speed: "12.5MiB/s", eta: "00:42"}} =
               YtdlpProgressParser.parse_line("download: 45.2%  12.5MiB/s 00:42")
    end

    test "parses progress template lines at 100 percent" do
      assert {:progress, %{pct: 100.0, speed: "8.23MiB/s", eta: "00:00"}} =
               YtdlpProgressParser.parse_line("download:100.0% 8.23MiB/s 00:00")
    end

    test "normalizes N/A values in progress template lines" do
      assert {:progress, %{pct: pct, speed: nil, eta: nil}} =
               YtdlpProgressParser.parse_line("download:  0.0%    N/A    N/A")

      assert pct == 0.0
    end

    test "parses standard download progress lines" do
      assert {:progress, %{pct: 45.2, speed: "12.5MiB/s", eta: "00:42"}} =
               YtdlpProgressParser.parse_line(
                 "[download]  45.2% of 1.23GiB at 12.5MiB/s ETA 00:42"
               )
    end

    test "parses merger post-processing lines" do
      assert {:post_processing, "[Merger] Merging formats..."} =
               YtdlpProgressParser.parse_line("[Merger] Merging formats...")
    end

    test "parses multiple post-processing markers" do
      for marker <- ["[ExtractAudio]", "[EmbedThumbnail]", "[Metadata]", "[MoveFiles]"] do
        assert {:post_processing, message} =
                 YtdlpProgressParser.parse_line("#{marker} processing output")

        assert message == "#{marker} processing output"
      end
    end

    test "parses error lines starting with ERROR:" do
      assert {:error_line, "ERROR: unable to download video"} =
               YtdlpProgressParser.parse_line("ERROR: unable to download video")
    end

    test "parses error lines containing [error]" do
      assert {:error_line, "[error] some error message"} =
               YtdlpProgressParser.parse_line("[error] some error message")
    end

    test "parses finished download lines" do
      assert {:finished, "[download] 100% of 1.23GiB"} =
               YtdlpProgressParser.parse_line("[download] 100% of 1.23GiB")
    end

    test "parses already-downloaded lines" do
      assert {:finished, "Video has already been downloaded"} =
               YtdlpProgressParser.parse_line("Video has already been downloaded")
    end

    test "returns unknown for unrecognized output" do
      assert :unknown = YtdlpProgressParser.parse_line("some random output")
    end

    test "returns unknown for an empty string" do
      assert :unknown = YtdlpProgressParser.parse_line("")
    end

    test "returns unknown for nil input" do
      assert :unknown = YtdlpProgressParser.parse_line(nil)
    end

    test "strips ANSI escape codes before parsing" do
      line = "\e[32mdownload: 45.2%  12.5MiB/s 00:42\e[0m"

      assert {:progress, %{pct: 45.2, speed: "12.5MiB/s", eta: "00:42"}} =
               YtdlpProgressParser.parse_line(line)
    end

    test "removes carriage returns before parsing" do
      line = "\r[download]  45.2% of 1.23GiB at 12.5MiB/s ETA 00:42\r"

      assert {:progress, %{pct: 45.2, speed: "12.5MiB/s", eta: "00:42"}} =
               YtdlpProgressParser.parse_line(line)
    end

    test "clamps percentages above 100" do
      assert {:progress, %{pct: 100.0, speed: "1.0MiB/s", eta: "00:00"}} =
               YtdlpProgressParser.parse_line("download: 150.5%  1.0MiB/s 00:00")
    end
  end

  describe "strip_ansi/1" do
    test "removes ANSI escape sequences from strings" do
      assert "download: 45.2%  12.5MiB/s 00:42" ==
               YtdlpProgressParser.strip_ansi("\e[1;32mdownload: 45.2%  12.5MiB/s 00:42\e[0m")
    end

    test "leaves plain strings unchanged" do
      assert "plain output" == YtdlpProgressParser.strip_ansi("plain output")
    end
  end
end
