defmodule Ytdarr.Services.YouTube.IdentifierParser do
  @moduledoc """
  Parses various YouTube channel identifier formats into a normalized tagged tuple.

  Accepts handles (`@dirty-civilian`), channel URLs, and raw channel IDs.
  Returns a tagged tuple indicating the identifier type so the caller can
  dispatch to the correct YouTube API parameter.

  ## Supported Formats

  | Input                                            | Result                              |
  |--------------------------------------------------|-------------------------------------|
  | `@dirty-civilian`                                | `{:handle, "@dirty-civilian"}`      |
  | `https://youtube.com/@dirty-civilian`            | `{:handle, "@dirty-civilian"}`      |
  | `https://www.youtube.com/@dirty-civilian`        | `{:handle, "@dirty-civilian"}`      |
  | `UCxxxxxxxxxxxxxxxxxxxxxxxx`                     | `{:channel_id, "UCxxxxxxx..."}`     |
  | `https://youtube.com/channel/UCxxxx`             | `{:channel_id, "UCxxxx"}`          |
  | `https://youtube.com/c/ChannelName`              | `{:handle, "@ChannelName"}`         |
  | `https://youtube.com/user/Username`              | `{:username, "Username"}`           |

  ## Examples

      iex> IdentifierParser.parse("@dirty-civilian")
      {:handle, "@dirty-civilian"}

      iex> IdentifierParser.parse("https://www.youtube.com/@dirty-civilian")
      {:handle, "@dirty-civilian"}

      iex> IdentifierParser.parse("UCsXVk37bltHxD1rDPwtNM8Q")
      {:channel_id, "UCsXVk37bltHxD1rDPwtNM8Q"}

      iex> IdentifierParser.parse("")
      {:error, :empty_input}
  """

  @youtube_hosts ~w(youtube.com www.youtube.com m.youtube.com)

  @doc """
  Parses a YouTube channel identifier string into a tagged tuple.

  Returns one of:
  - `{:channel_id, id}` — a raw YouTube channel ID (starts with `UC`)
  - `{:handle, handle}` — a YouTube handle (prefixed with `@`)
  - `{:username, username}` — a legacy YouTube username
  - `{:error, :empty_input}` — blank or nil input
  - `{:error, :unrecognized}` — input that doesn't match any known format
  """
  @spec parse(String.t() | nil) ::
          {:channel_id, String.t()}
          | {:handle, String.t()}
          | {:username, String.t()}
          | {:error, :empty_input | :unrecognized}
  def parse(nil), do: {:error, :empty_input}

  def parse(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:error, :empty_input}

      String.starts_with?(input, "@") ->
        parse_handle(input)

      looks_like_url?(input) ->
        parse_url(input)

      String.starts_with?(input, "UC") ->
        {:channel_id, input}

      true ->
        {:error, :unrecognized}
    end
  end

  defp parse_handle(handle) do
    # Validate handle has content after the @
    case String.trim_leading(handle, "@") do
      "" -> {:error, :unrecognized}
      _rest -> {:handle, handle}
    end
  end

  defp looks_like_url?(input) do
    String.contains?(input, "youtube.com") or String.starts_with?(input, "http")
  end

  defp parse_url(input) do
    # Normalize: add scheme if missing so URI.parse works
    normalized =
      cond do
        String.starts_with?(input, "http://") or String.starts_with?(input, "https://") ->
          input

        String.starts_with?(input, "//") ->
          "https:" <> input

        true ->
          "https://" <> input
      end

    uri = URI.parse(normalized)

    if uri.host in @youtube_hosts do
      parse_youtube_path(uri.path)
    else
      {:error, :unrecognized}
    end
  end

  defp parse_youtube_path(nil), do: {:error, :unrecognized}

  defp parse_youtube_path(path) do
    # Split path and remove empty segments
    segments =
      path
      |> String.split("/")
      |> Enum.reject(&(&1 == ""))

    case segments do
      # /channel/UCxxxx or /channel/UCxxxx/videos etc
      ["channel", channel_id | _] when byte_size(channel_id) > 0 ->
        if String.starts_with?(channel_id, "UC") do
          {:channel_id, channel_id}
        else
          {:error, :unrecognized}
        end

      # /@handle or /@handle/videos etc
      ["@" <> _ = handle | _] when byte_size(handle) > 1 ->
        {:handle, handle}

      # /c/ChannelName — YouTube custom URLs resolve like handles
      ["c", name | _] when byte_size(name) > 0 ->
        {:handle, "@" <> name}

      # /user/Username — legacy username format
      ["user", username | _] when byte_size(username) > 0 ->
        {:username, username}

      _ ->
        {:error, :unrecognized}
    end
  end
end
