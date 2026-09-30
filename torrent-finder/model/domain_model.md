# Torrent Finder: Domain Model

This document describes the domain model for Torrent Finder: the core entities, their relationships, and the search/filter pipeline, independent of the specific YTS/EZTV API implementation details.

```mermaid
classDiagram
    class SearchRequest {
        +string query
        +string imdbId
        +MediaType type
        +int minSeeds
        +Quality quality
        +int season
        +int episode
        +int[] episodes
        +ReleaseType release
        +Codec codec
        +ReleaseSource source
        +SortBy sort
        +int limit
        +MusicProvider musicSource
    }

    class MediaSource {
        <<interface>>
        +string name
        +fetch(SearchRequest) TorrentResult[]
    }

    class YtsSource {
        +string[] mirrorHosts
        +fetchByKeyword(query) TorrentResult[]
    }

    class EztvSource {
        +fetchRecentByKeyword(query) TorrentResult[]
        +fetchByImdbId(imdbId) TorrentResult[]
    }

    class InternetArchiveSource {
        +searchAudio(query) TorrentResult[]
    }

    class JamendoSource {
        +searchAudio(query) TorrentResult[]
    }

    class ImdbTitleResolver {
        +resolveExactTvSeries(query) imdbId
    }

    class TorrentResult {
        +string source
        +string title
        +Quality quality
        +Codec codec
        +ReleaseSource mediaSource
        +int season
        +int episode
        +int seeds
        +int peers
        +string size
        +string magnet
    }

    class ResultFilter {
        +apply(TorrentResult[], SearchRequest) TorrentResult[]
    }

    MediaSource <|.. YtsSource
    MediaSource <|.. EztvSource
    MediaSource <|.. InternetArchiveSource
    MediaSource <|.. JamendoSource
    SearchRequest --> MediaSource : dispatched to
    SearchRequest --> InternetArchiveSource : music query
    SearchRequest --> JamendoSource : optional music query
    SearchRequest --> ImdbTitleResolver : TV title resolution
    ImdbTitleResolver --> EztvSource : imdbId
    MediaSource --> TorrentResult : produces
    TorrentResult --> ResultFilter : filtered by
    ResultFilter --> TorrentResult : ranked output
```

## Domain Flow

```mermaid
flowchart TD
    Request(("SearchRequest")) --> IsMusic{type = music?}

    IsMusic -->|Yes| MusicProvider{music source?}
    MusicProvider -->|archive / all| ArchiveSearch["Internet Archive:<br/>search public audio"]
    MusicProvider -->|jamendo / all| JamendoSearch["Jamendo: search Creative Commons<br/>when API client ID is configured"]
    ArchiveSearch --> MusicOutput(("Music results with<br/>DOWNLOAD URLs"))
    JamendoSearch --> MusicOutput

    IsMusic -->|No| HasImdb{imdbId provided?}

    HasImdb -->|Yes| ImdbLookup["EZTV: fetch ALL torrents<br/>for exact show via imdb_id<br/>(precise, not keyword-limited)"]
    HasImdb -->|No| TypeRoute{type?}

    TypeRoute -->|movie / all| YtsFetch["YTS: fetch by query_term<br/>(true full-text search)"]
    TypeRoute -->|tv / all| ResolveTitle["Resolve exact TV title<br/>to IMDb TV-series ID"]
    ResolveTitle --> Resolved{IMDb ID found?}
    Resolved -->|Yes| ImdbLookup
    Resolved -->|No| EztvScan["EZTV fallback: page through recent<br/>torrents, match title substring<br/>(best-effort, recency-limited)"]

    ImdbLookup --> Raw
    YtsFetch --> Raw
    EztvScan --> Raw["Raw TorrentResult[]"]

    Raw --> Enrich["Enrich each result:<br/>extract quality, codec,<br/>season/episode, source<br/>from title"]

    Enrich --> FilterSeeds["Filter: seeds >= minSeeds"]
    FilterSeeds --> FilterQuality["Filter: quality match<br/>(if requested)"]
    FilterQuality --> FilterEpisode["Filter: season and one or more<br/>episode numbers (if requested)"]
    FilterEpisode --> FilterRelease["Filter: episode, full season,<br/>or multi-season pack"]
    FilterRelease --> FilterCodec["Filter: codec/source match<br/>(if requested)"]
    FilterCodec --> Sort["Sort by seeds or<br/>quality rank"]
    Sort --> Truncate["Truncate to limit"]
    Truncate --> Output(("Ranked TorrentResult[]"))
```

## Domain Concepts

### 1. TV Lookup Prefers an Exact IMDb Match
A TV title is first resolved through IMDb's title-suggestion endpoint. An exact TV-series match supplies the `imdb_id` for EZTV's precise lookup, which is paged through the complete indexed catalog. `--imdb` skips resolution and selects the show directly. The recent-torrents keyword scan remains a fallback only when an exact TV title cannot be resolved.

### 2. Enrichment Combines API Fields and Title Metadata
EZTV provides native `season`, `episode`, seed, peer, and byte-size fields. The domain uses those season/episode fields first, falling back to title extraction when absent. Quality, codec, release source, and release type are derived from the title so YTS and EZTV normalize into one `TorrentResult` shape.

### 3. Filtering is Additive and Order-Independent
Each filter (`minSeeds`, `quality`, `season`, `episode`/`episodes`, `release`, `codec`, `source`) narrows the candidate set independently; an unset filter is a no-op. `release` distinguishes individual episodes, full-season releases, and multi-season/complete packs.

### 4. "High Quality" is a Ranking, Not a Boolean
Rather than a single pass/fail definition, quality is expressed as a **rank** (`2160p > 1080p > 720p > 480p > SD`) used for `--sort quality`. Combined with `--min-seeds`, this lets the user trade off resolution against download health rather than treating "high quality" as one fixed threshold.

### 5. Music Uses Provider-Specific Download URLs
Music is an explicit `type = music` mode so the default movie/TV workflow remains unchanged. Internet Archive is available without configuration and returns legal collection torrent URLs. Jamendo is optional because its API requires a client ID; when configured through `JAMENDO_CLIENT_ID`, it returns the direct audio URL supplied by Jamendo. Music is not subject to torrent seeder or resolution filters.
