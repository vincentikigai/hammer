# Torrent Finder

A lightweight, OS-independent CLI to search and filter high quality torrents across public torrent APIs:

- **YTS** (`yts.mx`) for movies
- **EZTV** (`eztv.re`) for TV shows
- **Internet Archive** (`archive.org`) for public-domain and Creative Commons music
- **Jamendo** for Creative Commons music when configured with an API client ID
- **Prowlarr** for configured, self-hosted Torznab indexers
- **Jackett** for configured, self-hosted Torznab indexers

No external dependencies — uses only the Python standard library.

> **Use responsibly.** Only search for and download content you have the legal right to access (e.g. public domain works, Creative Commons releases, or media you already own). Respect copyright law in your jurisdiction.

## Requirements

- Python 3.7+
- Internet connection (no extra pip packages needed)

## Usage

```bash
python3 torrent_finder.py "<search terms>" [options]
```

### Search Types

**Movies** use YTS keyword search. Use `--type movie` to search movies only; movie results support
the shared filters such as `--quality`, `--min-seeds`, `--sort`, and `--limit`.

```bash
python3 torrent_finder.py "Inception" --type movie --quality 1080p --min-seeds 10
```

**TV shows** use EZTV. A TV title is resolved to an exact IMDb TV-series ID automatically, then
the tool retrieves EZTV's indexed catalog for that show. Use `--type tv` to search TV only. TV
results also support `--imdb`, `--season`, `--episode`, `--episodes`, and `--release`.

```bash
python3 torrent_finder.py "Numberblocks" --type tv --season 4 --episodes 1,3-5 --quality 720p
```

**Music** is an explicit mode: use `--type music`. Internet Archive works without setup and
returns collection `.torrent` download links. Jamendo is included when `JAMENDO_CLIENT_ID` is set
in the environment, and returns direct audio-download links where its API supplies them.

```bash
python3 torrent_finder.py "Sintel" --type music --music-source archive
python3 torrent_finder.py "ambient" --type music --music-source all
```

More music-search examples:

```powershell
# Search Internet Archive only; no account or setup required
python torrent_finder.py "ambient" --type music --music-source archive --limit 10

# Search every configured music provider
python torrent_finder.py "jazz" --type music --music-source all --limit 20

# Search Jamendo after setting its required API client ID
$env:JAMENDO_CLIENT_ID = "your-client-id"
python torrent_finder.py "electronic" --type music --music-source jamendo --limit 10
```

`--type all` is the default and searches movies and TV shows. TV-only filters have no effect on movie
results.

### Optional Indexers

Prowlarr and Jackett are optional local services. They are queried only when selected with
`--indexer`; no credentials are stored in this project. Configure them through environment variables:

```powershell
# Copy Prowlarr's Torznab feed URL and API key from its settings.
$env:PROWLARR_TORZNAB_URL = "http://localhost:9696/your-torznab-feed"
$env:PROWLARR_API_KEY = "your-prowlarr-api-key"

# Jackett uses its local service URL and API key.
$env:JACKETT_URL = "http://127.0.0.1:9117"
$env:JACKETT_API_KEY = "your-jackett-api-key"
```

```powershell
# Search only configured Prowlarr indexers
python torrent_finder.py "Sintel" --type movie --indexer prowlarr --min-seeds 0

# Search native APIs plus every configured Prowlarr and Jackett indexer
python torrent_finder.py "Numberblocks" --type tv --indexer all --season 4 --min-seeds 0
```

Use only indexers and content you are authorized to access. `--indexer native` is the default and
continues to use YTS/EZTV without either local service.

### Options

| Flag | Description | Default |
|---|---|---|
| `--type {movie,tv,music,all}` | Search movies, TV, music, or movies and TV | `all` |
| `--music-source {archive,jamendo,all}` | Music catalog to query; Jamendo requires `JAMENDO_CLIENT_ID` | `all` |
| `--indexer {native,prowlarr,jackett,all}` | Torrent backend; Prowlarr/Jackett require local configuration | `native` |
| `--min-seeds N` | Minimum seeder count to include a result | `5` |
| `--quality {2160p,1080p,720p,480p,all}` | Filter by resolution | `all` |
| `--imdb ID` | Look up a TV show directly by IMDb ID | — |
| `--season N` | Filter TV results by season number | — |
| `--episode N` | Filter TV results by one episode number | — |
| `--episodes LIST` | Filter TV results by episodes, e.g. `1,3,5-7` | — |
| `--release {episode,season,pack,all}` | Restrict TV results to individual episodes, full seasons, or packs | `all` |
| `--codec {x264,x265,any}` | Filter by video codec | `any` |
| `--source {web-dl,webrip,web,hdtv,bluray,brrip,any}` | Filter by release source | `any` |
| `--sort {seeds,quality}` | Sort results by seeder count or resolution | `seeds` |
| `--limit N` | Max number of results to print | `20` |

### Examples

Search for a movie in exactly 1080p with at least 20 seeders:

```bash
python3 torrent_finder.py "Big Buck Bunny" --quality 1080p --min-seeds 20
```

Find specific TV episodes. The title is resolved to an IMDb TV-series ID automatically:

```bash
python3 torrent_finder.py "Numberblocks" --type tv --season 4 --episodes 1,3-5 --release episode --quality 720p
```

Find full-season releases or multi-season packs:

```bash
python3 torrent_finder.py "some show" --type tv --season 2 --release season
python3 torrent_finder.py "some show" --type tv --release pack
```

Each torrent result includes the source, quality, seeds/peers, size, and a ready-to-use magnet link.
Music results include a `DOWNLOAD` URL rather than a magnet link. Internet Archive's URL points to
the collection torrent; Jamendo's URL is a direct audio download when available.

### Known limitation

EZTV's public API has no full-text search endpoint. For a TV title query, the tool first resolves
an exact IMDb TV-series match and uses EZTV's `imdb_id` endpoint, paging through its indexed show
catalog before filtering locally. If an exact title cannot be resolved, it falls back to scanning
the latest ~500 EZTV entries, so older shows may not appear in that fallback mode. Use `--imdb`
to select a specific show directly when a title is ambiguous.

