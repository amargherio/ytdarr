defmodule Ytdarr.Downloads.YtdlpProgressParser do
  @moduledoc """
  Pure helpers for turning yt-dlp stdout/stderr lines into structured download
  progress data.

  The parser normalizes each line before matching:

    * ANSI escape sequences are removed with `strip_ansi/1`
    * carriage returns (`\\r`) are removed
    * leading and trailing whitespace is trimmed

  Supported line formats, in matching order:

  1. `--progress-template` output, for example:

         download: 45.2%  12.5MiB/s 00:42
         download:100.0% 8.23MiB/s 00:00
         download:  0.0%    N/A    N/A

  2. Standard `[download]` progress lines, for example:

         [download]  45.2% of 1.23GiB at 12.5MiB/s ETA 00:42

  3. Post-processing markers such as `[Merger]`, `[ExtractAudio]`,
     `[EmbedSubtitle]`, `[EmbedThumbnail]`, `[Metadata]`, and similar yt-dlp
     steps.

  4. Error lines starting with `ERROR:` or containing `[error]`.

  5. Finished markers such as completed `[download] 100% ...` lines or
     `"has already been downloaded"`.

  Values like `N/A`, `Unknown`, `Unknown speed`, and `Unknown ETA` are returned
  as `nil`. Percentages above `100%` are clamped to `100.0`.

  ## Recommended yt-dlp configuration

  For the most reliable parsing, invoke yt-dlp with line-oriented progress
  output:

      --newline
      --progress-template "download:%(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s"

  `--newline` ensures progress updates are emitted as full lines instead of
  carriage-return rewritten terminal output.
  """

  @typedoc "Structured download progress information."
  @type progress_data :: %{pct: float(), speed: String.t() | nil, eta: String.t() | nil}

  @typedoc "The parsed result for a single yt-dlp output line."
  @type parse_result ::
          {:progress, progress_data()}
          | {:post_processing, String.t()}
          | {:finished, String.t()}
          | {:error_line, String.t()}
          | :unknown

  @ansi_regex ~r/\e(?:[@-Z\\-_]|\[[0-?]*[ -\/]*[@-~])/
  @unknown_value_regex ~r/^(?:N\/A|Unknown(?:\s+\w+)*)$/i

  @progress_template_regex ~r/^download:\s*(?<pct>\d+(?:\.\d+)?)%\s+(?<speed>.+?)\s+(?<eta>N\/A|Unknown(?:\s+\w+)*|\d{2}:\d{2}(?::\d{2})?)$/i
  @download_progress_regex ~r/^\[download\]\s+(?<pct>\d+(?:\.\d+)?)%\s+of\s+.+?\s+at\s+(?<speed>.+?)\s+ETA\s+(?<eta>N\/A|Unknown(?:\s+\w+)*|\d{2}:\d{2}(?::\d{2})?)(?:\s+.*)?$/i
  @finished_download_regex ~r/^\[download\]\s+(?<pct>\d+(?:\.\d+)?)%\s+of\b.+$/i
  @error_regex ~r/\[error\]/i

  @post_processing_markers [
    "[Merger]",
    "[ExtractAudio]",
    "[EmbedSubtitle]",
    "[EmbedThumbnail]",
    "[Metadata]",
    "[EmbedChapter]",
    "[FixupM3u8]",
    "[FixupM4a]",
    "[FixupStretched]",
    "[VideoRemuxer]",
    "[VideoConvertor]",
    "[SubtitlesConvertor]",
    "[ThumbnailsConvertor]",
    "[MoveFiles]",
    "[SplitChapters]"
  ]

  @doc """
  Parses a single yt-dlp output line into a structured event.

  Returns one of:

    * `{:progress, %{pct: float(), speed: String.t() | nil, eta: String.t() | nil}}`
    * `{:post_processing, message}`
    * `{:finished, message}`
    * `{:error_line, message}`
    * `:unknown`
  """
  @spec parse_line(String.t()) :: parse_result()
  def parse_line(line) when is_binary(line) do
    case normalize_line(line) do
      "" ->
        :unknown

      normalized ->
        parse_progress_template(normalized) ||
          parse_standard_download(normalized) ||
          parse_post_processing(normalized) ||
          parse_error(normalized) ||
          parse_finished(normalized) ||
          :unknown
    end
  end

  def parse_line(_), do: :unknown

  @doc """
  Removes ANSI escape sequences from a string.
  """
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(string) when is_binary(string) do
    Regex.replace(@ansi_regex, string, "")
  end

  defp normalize_line(line) do
    line
    |> strip_ansi()
    |> String.replace("\r", "")
    |> String.trim()
  end

  defp parse_progress_template(line) do
    case Regex.named_captures(@progress_template_regex, line) do
      %{"pct" => pct, "speed" => speed, "eta" => eta} ->
        {:progress,
         %{
           pct: parse_pct(pct),
           speed: normalize_optional_value(speed),
           eta: normalize_optional_value(eta)
         }}

      _ ->
        nil
    end
  end

  defp parse_standard_download(line) do
    case Regex.named_captures(@download_progress_regex, line) do
      %{"pct" => pct, "speed" => speed, "eta" => eta} ->
        {:progress,
         %{
           pct: parse_pct(pct),
           speed: normalize_optional_value(speed),
           eta: normalize_optional_value(eta)
         }}

      _ ->
        nil
    end
  end

  defp parse_post_processing(line) do
    if Enum.any?(@post_processing_markers, &String.contains?(line, &1)) do
      {:post_processing, line}
    end
  end

  defp parse_error(line) do
    if String.starts_with?(line, "ERROR:") or Regex.match?(@error_regex, line) do
      {:error_line, line}
    end
  end

  defp parse_finished(line) do
    cond do
      String.contains?(line, "has already been downloaded") ->
        {:finished, line}

      captures = Regex.named_captures(@finished_download_regex, line) ->
        pct = captures["pct"] |> parse_pct()

        if pct >= 100.0 do
          {:finished, line}
        end

      true ->
        nil
    end
  end

  defp normalize_optional_value(value) do
    value = String.trim(value)

    if value == "" or Regex.match?(@unknown_value_regex, value) do
      nil
    else
      value
    end
  end

  defp parse_pct(value) do
    case Float.parse(value) do
      {pct, _rest} -> min(pct, 100.0)
      :error -> 0.0
    end
  end
end
