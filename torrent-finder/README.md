# Torrent Finder

A lightweight, OS-independent CLI to search and filter high quality torrents across public torrent APIs:

- **YTS** (`yts.mx`) for movies
- **EZTV** (`eztv.re`) for TV shows

No external dependencies — uses only the Python standard library.

> **Use responsibly.** Only search for and download content you have the legal right to access (e.g. public domain works, Creative Commons releases, or media you already own). Respect copyright law in your jurisdiction.

## Requirements

- Python 3.7+
- Internet connection (no extra pip packages needed)

## Usage

```bash
python3 torrent_finder.py "<search terms>" [options]
```

### Options

| Flag | Description | Default |
|---|---|---|
| `--type {movie,tv,all}` | Restrict search to YTS (movie), EZTV (tv), or both | `all` |
| `--min-seeds N` | Minimum seeder count to include a result | `5` |
| `--quality {2160p,1080p,720p,480p,all}` | Filter by resolution | `all` |
| `--sort {seeds,quality}` | Sort results by seeder count or resolution | `seeds` |
| `--limit N` | Max number of results to print | `20` |

### Examples

Search for a movie, only 1080p+ with at least 20 seeders:

```bash
python3 torrent_finder.py "Big Buck Bunny" --quality 1080p --min-seeds 20
```

Search TV shows only, sorted by quality:

```bash
python3 torrent_finder.py "some show" --type tv --sort quality
```

Each result includes the source, quality, seeds/peers, size, and a ready-to-use magnet link.
