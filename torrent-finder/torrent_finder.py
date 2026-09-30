#!/usr/bin/env python3
"""Search and filter torrents by quality/seeders across public torrent APIs (YTS movies, EZTV TV shows)."""
import argparse
import math
import os
import re
import sys
import urllib.parse
import urllib.request
import json

YTS_HOSTS = ["yts.mx", "yts.am", "yts.lt"]
EZTV_API = "https://eztv.re/api/get-torrents"
IMDB_SUGGESTION_URL = "https://v3.sg.media-imdb.com/suggestion/x"
INTERNET_ARCHIVE_SEARCH_API = "https://archive.org/advancedsearch.php"
JAMENDO_TRACKS_API = "https://api.jamendo.com/v3.0/tracks/"

QUALITY_RANK = {"2160p": 4, "1080p": 3, "720p": 2, "480p": 1, "SD": 0}

TRACKERS = [
    "udp://tracker.opentrackr.org:1337/announce",
    "udp://open.demonii.com:1337/announce",
    "udp://tracker.openbittorrent.com:6969/announce",
    "udp://exodus.desync.com:6969/announce",
]


def http_get_json(url, params, timeout=15):
    query = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{url}?{query}", headers={"User-Agent": "torrent-finder/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_get_json_retrying(url, params, timeout=25, retries=1):
    last_error = None
    for attempt in range(retries + 1):
        try:
            return http_get_json(url, params, timeout=timeout)
        except Exception as exc:
            last_error = exc
    raise last_error


def build_magnet(info_hash, display_name):
    if not info_hash:
        return ""
    trackers = "".join(f"&tr={urllib.parse.quote(t)}" for t in TRACKERS)
    return f"magnet:?xt=urn:btih:{info_hash}&dn={urllib.parse.quote(display_name)}{trackers}"


def extract_quality(title):
    match = re.search(r"(2160p|1080p|720p|480p)", title, re.IGNORECASE)
    return match.group(1).lower() if match else "SD"


def extract_season_episode(title, torrent=None):
    if torrent:
        season = torrent.get("season")
        episode = torrent.get("episode")
        if season and episode and season.isdigit() and episode.isdigit():
            return int(season), int(episode)

    match = re.search(r"[Ss](\d{1,2})[Ee](\d{1,3})", title)
    if not match:
        return None, None
    return int(match.group(1)), int(match.group(2))


def extract_codec(title):
    match = re.search(r"(x265|x264|HEVC|AVC)", title, re.IGNORECASE)
    if not match:
        return "any"
    codec = match.group(1).lower()
    return "x265" if codec in ("x265", "hevc") else "x264"


def extract_source(title):
    match = re.search(r"(WEB-DL|WEBRip|WEB|HDTV|BluRay|BRRip)", title, re.IGNORECASE)
    return match.group(1).lower() if match else "any"


def extract_release_type(title, episode):
    if re.search(r"\bpack\b|\bcomplete\b|[Ss]\d{1,2}\s*[-+]\s*[Ss]?\d{1,2}", title, re.IGNORECASE):
        return "pack"
    if episode is None and re.search(r"\bseason\s*\d+\b|[Ss]\d{1,2}(?![Ee]\d)", title, re.IGNORECASE):
        return "season"
    return "episode"


def parse_episode_list(value):
    episodes = set()
    for item in value.split(","):
        item = item.strip()
        match = re.fullmatch(r"(\d+)(?:-(\d+))?", item)
        if not match:
            raise ValueError(f"invalid episode selector: {item}")
        start = int(match.group(1))
        end = int(match.group(2) or start)
        if start < 1 or end < start:
            raise ValueError(f"invalid episode range: {item}")
        episodes.update(range(start, end + 1))
    return episodes


def normalize_imdb_id(imdb_id):
    return re.sub(r"^tt0*", "", imdb_id.strip(), flags=re.IGNORECASE)


def resolve_tv_imdb_id(query):
    url = f"{IMDB_SUGGESTION_URL}/{urllib.parse.quote(query)}.json"
    try:
        data = http_get_json(url, {})
    except Exception as exc:
        print(f"Warning: IMDb title lookup failed ({exc})", file=sys.stderr)
        return None

    query_normalized = query.casefold().strip()
    for candidate in data.get("d", []):
        if candidate.get("q") != "TV series":
            continue
        if candidate.get("l", "").casefold().strip() == query_normalized:
            return candidate.get("id")
    return None


def format_size(num_bytes):
    if not num_bytes:
        return "N/A"
    size = float(num_bytes)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} PB"


def search_internet_archive_music(query, limit):
    term = query.replace('"', r'\"')
    params = [
        ("q", f'mediatype:audio AND (title:"{term}" OR creator:"{term}")'),
        ("fl[]", "identifier"),
        ("fl[]", "title"),
        ("fl[]", "creator"),
        ("fl[]", "year"),
        ("fl[]", "downloads"),
        ("sort[]", "downloads desc"),
        ("rows", str(min(limit, 50))),
        ("output", "json"),
    ]
    try:
        data = http_get_json(INTERNET_ARCHIVE_SEARCH_API, params)
    except Exception as exc:
        print(f"Warning: Internet Archive music search failed ({exc})", file=sys.stderr)
        return []

    results = []
    for item in data.get("response", {}).get("docs", []):
        identifier = item.get("identifier")
        if not identifier:
            continue
        title = item.get("title", identifier)
        creator = item.get("creator")
        if creator:
            title = f"{creator} - {title}"
        results.append({
            "source": "ARCHIVE",
            "title": title,
            "quality": "N/A",
            "seeds": item.get("downloads", 0),
            "peers": 0,
            "size": item.get("year", "N/A"),
            "magnet": f"https://archive.org/download/{identifier}/{identifier}_archive.torrent",
            "is_torrent": False,
        })
    return results


def search_jamendo_music(query, limit):
    client_id = os.getenv("JAMENDO_CLIENT_ID")
    if not client_id:
        print("Warning: Jamendo skipped; set JAMENDO_CLIENT_ID to enable it", file=sys.stderr)
        return []
    try:
        data = http_get_json(JAMENDO_TRACKS_API, {
            "client_id": client_id,
            "format": "json",
            "limit": min(limit, 200),
            "search": query,
        })
    except Exception as exc:
        print(f"Warning: Jamendo music search failed ({exc})", file=sys.stderr)
        return []

    results = []
    for track in data.get("results", []):
        title = track.get("name", "Unknown")
        artist = track.get("artist_name")
        if artist:
            title = f"{artist} - {title}"
        results.append({
            "source": "JAMENDO",
            "title": title,
            "quality": "N/A",
            "seeds": 0,
            "peers": 0,
            "size": track.get("duration", "N/A"),
            "magnet": track.get("audiodownload") or track.get("audio", ""),
            "is_torrent": False,
        })
    return results


def search_music(query, limit, music_source):
    results = []
    if music_source in ("archive", "all"):
        results.extend(search_internet_archive_music(query, limit))
    if music_source in ("jamendo", "all"):
        results.extend(search_jamendo_music(query, limit))
    return results


def search_yts(query, limit):
    params = {
        "query_term": query,
        "limit": min(limit, 50),
        "sort_by": "seeds",
        "order_by": "desc",
    }
    data = None
    last_error = None
    for host in YTS_HOSTS:
        try:
            data = http_get_json(f"https://{host}/api/v2/list_movies.json", params)
            break
        except Exception as exc:
            last_error = exc

    if data is None:
        print(f"Warning: YTS search failed ({last_error})", file=sys.stderr)
        return []

    movies = (data.get("data") or {}).get("movies") or []
    results = []
    for movie in movies:
        title = movie.get("title_long", movie.get("title", "Unknown"))
        for torrent in movie.get("torrents", []):
            results.append({
                "source": "YTS",
                "title": title,
                "quality": (torrent.get("quality") or "SD").lower(),
                "seeds": torrent.get("seeds", 0),
                "peers": torrent.get("peers", 0),
                "size": torrent.get("size", "N/A"),
                "magnet": build_magnet(torrent.get("hash"), title),
            })
    return results


EZTV_MAX_PAGES = 5  # EZTV's API has no full-text search, so we page through recent torrents client-side


def search_eztv(query, limit):
    query_lower = query.lower()
    results = []
    for page in range(1, EZTV_MAX_PAGES + 1):
        try:
            data = http_get_json_retrying(EZTV_API, {"limit": 100, "page": page})
        except Exception as exc:
            print(f"Warning: EZTV page {page} failed, skipping ({exc})", file=sys.stderr)
            continue

        torrents = data.get("torrents") or []
        if not torrents:
            break

        for torrent in torrents:
            title = torrent.get("title", "")
            if query_lower not in title.lower():
                continue
            season, episode = extract_season_episode(title, torrent)
            results.append({
                "source": "EZTV",
                "title": title,
                "quality": extract_quality(title),
                "codec": extract_codec(title),
                "media_source": extract_source(title),
                "season": season,
                "episode": episode,
                "seeds": torrent.get("seeds", 0),
                "peers": torrent.get("peers", 0),
                "size": format_size(int(torrent.get("size_bytes", 0) or 0)),
                "magnet": torrent.get("magnet_url", ""),
            })

        if len(results) >= limit:
            break
    return results


def search_eztv_by_imdb(imdb_id, limit):
    imdb_id = normalize_imdb_id(imdb_id)
    results = []
    page = 1
    total_pages = None
    while total_pages is None or page <= total_pages:
        try:
            data = http_get_json_retrying(EZTV_API, {"imdb_id": imdb_id, "limit": 100, "page": page})
        except Exception as exc:
            print(f"Warning: EZTV IMDb lookup page {page} failed, skipping ({exc})", file=sys.stderr)
            if total_pages is None:
                break
            page += 1
            continue

        total_pages = math.ceil(int(data.get("torrents_count", 0)) / 100)

        torrents = data.get("torrents") or []
        if not torrents:
            break

        for torrent in torrents:
            title = torrent.get("title", "")
            season, episode = extract_season_episode(title, torrent)
            results.append({
                "source": "EZTV",
                "title": title,
                "quality": extract_quality(title),
                "codec": extract_codec(title),
                "media_source": extract_source(title),
                "season": season,
                "episode": episode,
                "seeds": torrent.get("seeds", 0),
                "peers": torrent.get("peers", 0),
                "size": format_size(int(torrent.get("size_bytes", 0) or 0)),
                "magnet": torrent.get("magnet_url", ""),
            })
        page += 1
    return results


def filter_and_sort(results, min_seeds, quality, sort_by, season=None, episode=None, episodes=None,
                    release="all", codec="any", media_source="any"):
    filtered = [r for r in results if not r.get("is_torrent", True) or r["seeds"] >= min_seeds]
    if quality != "all":
        filtered = [r for r in filtered if not r.get("is_torrent", True) or r["quality"] == quality]
    if season is not None:
        filtered = [r for r in filtered if r.get("season") == season]
    if episode is not None:
        filtered = [r for r in filtered if r.get("episode") == episode]
    if episodes:
        filtered = [r for r in filtered if r.get("episode") in episodes]
    if release != "all":
        filtered = [r for r in filtered if extract_release_type(r["title"], r.get("episode")) == release]
    if codec != "any":
        filtered = [r for r in filtered if r.get("codec", "any") == codec]
    if media_source != "any":
        filtered = [r for r in filtered if r.get("media_source", "any") == media_source]

    if sort_by == "quality":
        filtered.sort(key=lambda r: (QUALITY_RANK.get(r["quality"], 0), r["seeds"]), reverse=True)
    else:
        filtered.sort(key=lambda r: r["seeds"], reverse=True)
    return filtered


def print_results(results, limit):
    if not results:
        print("No torrents matched the given filters.")
        return

    header = f'{"SRC":<5} {"QUALITY":<8} {"SEEDS":<7} {"PEERS":<7} {"SIZE":<10} TITLE'
    print(header)
    print("-" * len(header))
    for r in results[:limit]:
        print(f'{r["source"]:<5} {r["quality"]:<8} {r["seeds"]:<7} {r["peers"]:<7} {str(r["size"]):<10} {r["title"]}')
        if r["magnet"]:
            label = "MAGNET" if r.get("is_torrent", True) else "DOWNLOAD"
            print(f'      {label}: {r["magnet"]}')


def main():
    parser = argparse.ArgumentParser(
        description="Search and filter high quality torrents (movies via YTS, TV shows via EZTV). "
                     "Only use this tool to find torrents you have the legal right to download."
    )
    parser.add_argument("query", nargs="?", default=None, help="Search keywords (movie or TV show title)")
    parser.add_argument("--imdb", help="EZTV: look up a TV show by IMDb ID (e.g. tt0944947 or 944947) "
                                       "instead of scanning recent torrents by keyword")
    parser.add_argument("--type", choices=["movie", "tv", "music", "all"], default="all",
                        help="Media type to search")
    parser.add_argument("--music-source", choices=["archive", "jamendo", "all"], default="all",
                        help="Music catalog to search (default: all configured sources)")
    parser.add_argument("--min-seeds", type=int, default=5, help="Minimum seeder count (default: 5)")
    parser.add_argument("--quality", choices=["2160p", "1080p", "720p", "480p", "all"], default="all",
                         help="Filter by resolution (default: all)")
    parser.add_argument("--season", type=int, default=None, help="EZTV: filter by season number")
    parser.add_argument("--episode", type=int, default=None, help="EZTV: filter by episode number")
    parser.add_argument("--episodes", help="EZTV: filter by episodes, e.g. 1,3,5-7")
    parser.add_argument("--release", choices=["episode", "season", "pack", "all"], default="all",
                        help="EZTV: filter individual episodes, full seasons, or multi-season packs")
    parser.add_argument("--codec", choices=["x264", "x265", "any"], default="any", help="Filter by video codec")
    parser.add_argument("--source", choices=["web-dl", "webrip", "web", "hdtv", "bluray", "brrip", "any"],
                         default="any", help="Filter by release source")
    parser.add_argument("--sort", choices=["seeds", "quality"], default="seeds", help="Sort order (default: seeds)")
    parser.add_argument("--limit", type=int, default=20, help="Max results to display (default: 20)")
    args = parser.parse_args()

    if not args.imdb and not args.query:
        parser.error("provide a search query or --imdb <id>")
    if args.episode is not None and args.episodes:
        parser.error("use either --episode or --episodes, not both")
    try:
        episodes = parse_episode_list(args.episodes) if args.episodes else None
    except ValueError as exc:
        parser.error(str(exc))

    results = []
    if args.imdb:
        results.extend(search_eztv_by_imdb(args.imdb, args.limit * 2))
    else:
        if args.type in ("movie", "all"):
            results.extend(search_yts(args.query, args.limit * 2))
        if args.type in ("tv", "all"):
            imdb_id = resolve_tv_imdb_id(args.query)
            if imdb_id:
                results.extend(search_eztv_by_imdb(imdb_id, args.limit * 2))
            else:
                results.extend(search_eztv(args.query, args.limit * 2))
        if args.type == "music":
            results.extend(search_music(args.query, args.limit * 2, args.music_source))

    filtered = filter_and_sort(results, args.min_seeds, args.quality, args.sort,
                               season=args.season, episode=args.episode, episodes=episodes, release=args.release,
                               codec=args.codec, media_source=args.source)
    print_results(filtered, args.limit)


if __name__ == "__main__":
    main()
