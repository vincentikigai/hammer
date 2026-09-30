#!/usr/bin/env python3
"""Search and filter torrents by quality/seeders across public torrent APIs (YTS movies, EZTV TV shows)."""
import argparse
import re
import sys
import urllib.parse
import urllib.request
import json

YTS_API = "https://yts.mx/api/v2/list_movies.json"
EZTV_API = "https://eztv.re/api/get-torrents"

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


def build_magnet(info_hash, display_name):
    if not info_hash:
        return ""
    trackers = "".join(f"&tr={urllib.parse.quote(t)}" for t in TRACKERS)
    return f"magnet:?xt=urn:btih:{info_hash}&dn={urllib.parse.quote(display_name)}{trackers}"


def extract_quality(title):
    match = re.search(r"(2160p|1080p|720p|480p)", title, re.IGNORECASE)
    return match.group(1).lower() if match else "SD"


def format_size(num_bytes):
    if not num_bytes:
        return "N/A"
    size = float(num_bytes)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} PB"


def search_yts(query, limit):
    try:
        data = http_get_json(YTS_API, {
            "query_term": query,
            "limit": min(limit, 50),
            "sort_by": "seeds",
            "order_by": "desc",
        })
    except Exception as exc:
        print(f"Warning: YTS search failed ({exc})", file=sys.stderr)
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


def search_eztv(query, limit):
    try:
        data = http_get_json(EZTV_API, {"limit": min(limit, 100), "page": 1})
    except Exception as exc:
        print(f"Warning: EZTV search failed ({exc})", file=sys.stderr)
        return []

    torrents = data.get("torrents") or []
    query_lower = query.lower()
    results = []
    for torrent in torrents:
        title = torrent.get("title", "")
        if query_lower not in title.lower():
            continue
        results.append({
            "source": "EZTV",
            "title": title,
            "quality": extract_quality(title),
            "seeds": torrent.get("seeds", 0),
            "peers": torrent.get("peers", 0),
            "size": format_size(int(torrent.get("size_bytes", 0) or 0)),
            "magnet": torrent.get("magnet_url", ""),
        })
    return results


def filter_and_sort(results, min_seeds, quality, sort_by):
    filtered = [r for r in results if r["seeds"] >= min_seeds]
    if quality != "all":
        filtered = [r for r in filtered if r["quality"] == quality]

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
            print(f'      {r["magnet"]}')


def main():
    parser = argparse.ArgumentParser(
        description="Search and filter high quality torrents (movies via YTS, TV shows via EZTV). "
                     "Only use this tool to find torrents you have the legal right to download."
    )
    parser.add_argument("query", help="Search keywords (movie or TV show title)")
    parser.add_argument("--type", choices=["movie", "tv", "all"], default="all", help="Media type to search")
    parser.add_argument("--min-seeds", type=int, default=5, help="Minimum seeder count (default: 5)")
    parser.add_argument("--quality", choices=["2160p", "1080p", "720p", "480p", "all"], default="all",
                         help="Filter by resolution (default: all)")
    parser.add_argument("--sort", choices=["seeds", "quality"], default="seeds", help="Sort order (default: seeds)")
    parser.add_argument("--limit", type=int, default=20, help="Max results to display (default: 20)")
    args = parser.parse_args()

    results = []
    if args.type in ("movie", "all"):
        results.extend(search_yts(args.query, args.limit * 2))
    if args.type in ("tv", "all"):
        results.extend(search_eztv(args.query, args.limit * 2))

    filtered = filter_and_sort(results, args.min_seeds, args.quality, args.sort)
    print_results(filtered, args.limit)


if __name__ == "__main__":
    main()
