#!/usr/bin/env bash
set -euo pipefail
cd /tmp
mode="${1:?Expected runtime or build}"
while read -r component version digest url; do
  [[ -n "$component" && "$component" != \#* ]] || continue
  if [[ "$mode" == runtime && "$component" != yt-dlp ]]; then continue; fi
  if [[ "$mode" == build && "$component" == yt-dlp ]]; then continue; fi
  curl --fail --location --retry 3 "$url" --output "$component.download"
  printf '%s  %s\n' "$digest" "$component.download" | sha256sum --check -
  case "$component" in
    yt-dlp) install -m 0755 "$component.download" /usr/local/bin/yt-dlp ;;
    otp)
      expected=""
      while read -r name value; do [[ "$name" != erlang ]] || expected="$value"; done < /build-inputs/.tool-versions
      [[ "$version" == "$expected" ]] || { echo 'OTP checksum lock differs from .tool-versions' >&2; exit 1; }
      tar -xzf "$component.download"
      (
        cd "otp_src_$version"
        export CFLAGS='-O2 -march=x86-64 -mtune=generic'
        export CXXFLAGS="$CFLAGS"
        ./configure --prefix=/usr/local --without-javac --without-wx --without-odbc
        make -j"${NATIVE_BUILD_JOBS:-4}"
        make install
      )
      rm -rf "otp_src_$version"
      ;;
    elixir)
      expected=""
      while read -r name value; do [[ "$name" != elixir ]] || expected="${value%%-otp-*}"; done < /build-inputs/.tool-versions
      [[ "$version" == "$expected" ]] || { echo 'Elixir checksum lock differs from .tool-versions' >&2; exit 1; }
      mkdir -p /opt/elixir
      unzip -q "$component.download" -d /opt/elixir
      ;;
    *) echo "Unknown locked download: $component" >&2; exit 1 ;;
  esac
  rm "$component.download"
done < /build-inputs/native-downloads.tsv
