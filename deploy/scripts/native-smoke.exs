defmodule Ytdarr.NativeSmokeMedia do
  def init(opts), do: opts

  def call(conn, opts) do
    if Plug.Conn.get_req_header(conn, "x-native-smoke") != ["quoted value"] do
      raise "Settings-defined yt-dlp header was not preserved"
    end

    conn
    |> Plug.Conn.put_resp_content_type("video/mp4")
    |> Plug.Conn.send_file(200, Keyword.fetch!(opts, :media))
  end
end

alias Ytdarr.{Content, Settings}
root = System.fetch_env!("NATIVE_SMOKE_ROOT")
Application.put_env(:bcrypt_elixir, :log_rounds, 4)

Application.put_env(
  :ytdarr,
  Oban,
  Keyword.put(Application.fetch_env!(:ytdarr, Oban), :testing, :manual)
)

{:ok, _} = Application.ensure_all_started(:ytdarr)
true = Bcrypt.verify_pass("native-smoke", Bcrypt.hash_pwd_salt("native-smoke"))
%{rows: [[1]]} = Ecto.Adapters.SQL.query!(Ytdarr.Repo, "SELECT 1")
32 = byte_size(:crypto.strong_rand_bytes(32))

%Req.Response{status: 200} =
  Req.get!("http://127.0.0.1:#{System.fetch_env!("PORT")}/health/ready")

media = Path.join(root, "fixture.mp4")

{_, 0} =
  System.cmd(
    "ffmpeg",
    [
      "-hide_banner",
      "-loglevel",
      "error",
      "-f",
      "lavfi",
      "-i",
      "color=c=black:s=32x32:d=0.2",
      "-c:v",
      "mpeg4",
      media
    ], stderr_to_stdout: true)

{:ok, server} =
  Bandit.start_link(plug: {Ytdarr.NativeSmokeMedia, [media: media]}, port: 0, ip: {127, 0, 0, 1})

{:ok, {_ip, port}} = ThousandIsland.listener_info(server)
{:ok, _} = Settings.create_media_root_folder(%{path: root})
{group, 0} = System.cmd("id", ["-gn"])
{:ok, _} = Settings.put_setting("media.owner_group", String.trim(group))
{:ok, _} = Settings.put_setting("media.file_mode", "0644")
{:ok, _} = Settings.put_setting("media.directory_mode", "0755")

{:ok, _} =
  Settings.create_yt_dlp_param_set(%{
    name: "Native smoke",
    format: "best",
    extra_args: "--ignore-config\n--add-header \"X-Native-Smoke: quoted value\"",
    is_default: true
  })

{:ok, channel} =
  Content.create_channel(%{
    name: "Native smoke",
    external_id: "native-smoke",
    url: "http://127.0.0.1:#{port}",
    platform: "YouTube",
    is_monitored: false
  })

{:ok, video} =
  Content.create_video(channel.id, %{
    title: "Native smoke",
    external_id: "native-smoke-video",
    url: "http://127.0.0.1:#{port}/fixture.mp4",
    upload_date: Date.utc_today()
  })

{:ok, job} = Content.queue_video_download(video.id, channel.id)
:ok = Ytdarr.ObanWorkers.VideoDownloader.perform(job)
video = Content.get_video!(video.id)
true = video.is_downloaded
true = File.regular?(video.download_path)
true = File.stat!(video.download_path).size > 0
GenServer.stop(server)

IO.puts(
  "PASS native release: SQLite, bcrypt, crypto, migration, readiness, and real settings-driven yt-dlp/ffmpeg download"
)
