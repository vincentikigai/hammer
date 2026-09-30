# Torrent Finder Flowchart

```mermaid
flowchart TD
    Start([Run torrent_finder.py]) --> ParseArgs["Parse CLI Args<br/>- query / --imdb / --type<br/>- music source / TV filters<br/>- shared filters and output limit"]

    ParseArgs --> IsMusic{--type music?}
    IsMusic -->|Yes| MusicSource{--music-source?}
    MusicSource -->|archive or all| Archive["Search Internet Archive<br/>public-domain / CC audio"]
    MusicSource -->|jamendo or all| Jamendo["Search Jamendo<br/>when client ID is configured"]
    Archive --> MusicOutput["Print music results<br/>with DOWNLOAD URLs"]
    Jamendo --> MusicOutput

    IsMusic -->|No| HasImdb{--imdb provided?}
    HasImdb -->|Yes| ImdbLookup["EZTV: fetch every page for<br/>the exact show via imdb_id"]
    HasImdb -->|No| TypeCheck{--type value?}

    TypeCheck -->|movie or all| YTS["Search YTS<br/>(movies)"]
    TypeCheck -->|tv or all| ImdbResolve["Resolve exact TV title<br/>to IMDb ID"]

    YTS --> YTSHost["Try YTS host<br/>yts.mx -> yts.am -> yts.lt"]
    YTSHost --> YTSResult{Request<br/>succeeded?}
    YTSResult -->|No, all hosts failed| YTSWarn["Print warning to stderr<br/>Return empty list"]
    YTSResult -->|Yes| YTSParse["Parse movies + torrents<br/>Build magnet links"]
    YTSParse --> Combine

    ImdbResolve --> FoundImdb{Exact TV series<br/>match found?}
    FoundImdb -->|Yes| ImdbLookup
    FoundImdb -->|No| EZTVPage["Fallback: fetch page N of<br/>recent torrents (up to 5 pages)"]
    EZTVPage --> EZTVMatch{Title contains<br/>query keywords?}
    EZTVMatch -->|Yes| EZTVCollect["Collect result<br/>Extract quality from title"]
    EZTVMatch -->|No| EZTVNext
    EZTVCollect --> EZTVEnough{Enough results<br/>or no more pages?}
    EZTVNext["Skip torrent"] --> EZTVEnough
    EZTVEnough -->|No| EZTVPage
    EZTVEnough -->|Yes| Combine

    ImdbLookup --> Combine
    YTSWarn --> Combine["Combine YTS + EZTV<br/>results"]

    Combine --> FilterSeeds["Filter: seeds >= --min-seeds"]
    FilterSeeds --> FilterQuality{--quality != all?}
    FilterQuality -->|Yes| KeepQuality["Keep only matching<br/>resolution"]
    FilterQuality -->|No| FilterTv
    KeepQuality --> FilterTv["Filter TV: season, episode(s),<br/>release, codec, source"]
    FilterTv --> Sort["Sort by --sort<br/>(seeds or quality rank)"]

    Sort --> Truncate["Truncate to --limit"]
    Truncate --> HasResults{Any results?}
    HasResults -->|No| PrintEmpty["Print:<br/>'No torrents matched...'"]
    HasResults -->|Yes| PrintTable["Print torrent table:<br/>source, quality, seeds,<br/>peers, size, title, magnet"]

    PrintEmpty --> End([Exit])
    PrintTable --> End
    MusicOutput --> End
```

## Process Flow

1. **Argument parsing** — read the query/IMDb ID, media type, music provider, TV filters, and shared result options.
2. **YTS search (movies)** — query term is sent directly to the YTS API; tries `yts.mx`, then falls back to `yts.am`/`yts.lt` mirrors if the primary domain is unreachable.
3. **EZTV search (TV shows)** — an exact TV title is first resolved to an IMDb ID and EZTV returns all indexed torrents for that show, paged to completion. If no exact title match is available, the tool falls back to scanning recent torrents (up to 5 pages of 100).
4. **Music search** — `--type music` queries Internet Archive and, when configured, Jamendo. Results provide download URLs rather than torrent magnets.
5. **Combine results** from whichever movie/TV sources were selected via `--type`.
6. **Filter** movie/TV results by minimum seeders, resolution, season, episode(s), release type, codec, and source as requested.
7. **Sort and print** the top `--limit` movie/TV results as a table with magnet links.
