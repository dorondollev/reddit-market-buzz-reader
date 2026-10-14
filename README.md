# reddit-market-buzz-reader

This repository contains the public Reddit API access component used by a private, personal, non-commercial market analysis application.

It is a small, standalone, read-only connector. It does not contain, and is not, the application that consumes its output.

## Architecture

```
Reddit
  -> this public, read-only connector
  -> minimal structured per-post records (JSONL)
  -> a separate private, personal application
  -> derived, aggregate market-discussion statistics
```

This repository is only the first step in that chain. It does not compute aggregate statistics itself - it emits one minimal record per post, and a separate private application (not part of this repository) is responsible for aggregating those records over time.

## What this is

- **Personal use.** Built and operated by a single individual for personal, non-commercial research.
- **Non-commercial.** No product, no service, no monetization, no resale of Reddit data.
- **Read-only.** Reddit content retrieval uses `GET` requests only. OAuth token acquisition uses `POST` (as required by Reddit's own token endpoint), but this is not a write action against Reddit content or users - this connector never posts, votes, sends messages, or takes any moderation action.
- **Scope: a small, fixed list of public finance-related subreddits.** Currently:
  - `r/stocks`
  - `r/investing`
  - `r/wallstreetbets`

  This is not a global search across all of Reddit, and not a per-ticker query across hundreds of symbols — it reads a small, fixed set of community streams.

## What it does and does not do

- No posting, voting, messaging, or moderation actions of any kind.
- No user profiling or attempt to identify individuals.
- No resale or redistribution of Reddit data.
- No use of Reddit content to train any AI/LLM model.
- No production credentials are committed to this repository. Credentials are supplied only through environment variables at runtime (see `config.example`).
- Raw Reddit post text is read only in memory, to extract explicit stock-ticker mentions (e.g. `$AAPL`), and is then discarded - it is not part of this connector's output and is not retained.

## What it outputs, and what it is used for

This connector's own output is a minimal, structured, per-post record (see "Output" below) - not an aggregate statistic. A separate, private, personal application (not part of this repository, and not public) reads that per-post output over time and computes the actual aggregate, derived market-discussion statistics (e.g. mention counts and engagement trends per stock ticker). That application's code is not part of this repository.

## Running it

Requires Perl 5.x with the core modules `HTTP::Tiny`, `JSON::PP`, and `MIME::Base64` (bundled with any standard modern Perl installation — no additional CPAN dependencies).

```
REDDIT_CLIENT_ID=... REDDIT_CLIENT_SECRET=... REDDIT_USER_AGENT="..." perl reddit_buzz_reader.pl
```

See `config.example` for the full list of environment variables and their purpose.

## Output

One JSON object per line (JSONL) on stdout, one record per post. Each record contains only:

- `subreddit`
- `post_id`
- `created_utc`
- `score`
- `num_comments`
- `cashtags` (explicit `$TICKER`-style mentions found in the post's title/body; the underlying raw text itself is not included)
- `permalink`

No raw title, no post body, no author/username, and no other user identifiers are included in the output.

## License

See repository owner for licensing terms.
