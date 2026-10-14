# reddit-market-buzz-reader

This repository contains the public Reddit API access component used by a private, personal, non-commercial market analysis application.

It is a small, standalone, read-only connector. It does not contain, and is not, the application that consumes its output.

## What this is

- **Personal use.** Built and operated by a single individual for personal, non-commercial research.
- **Non-commercial.** No product, no service, no monetization, no resale of Reddit data.
- **Read-only.** This connector only performs `GET` requests against the Reddit Data API. It never posts, votes, sends messages, or takes any moderation action.
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
- Raw Reddit post/comment text is read only in memory, to extract explicit stock-ticker mentions (e.g. `$AAPL`), and is not intended for long-term storage. The intended output is derived, aggregate market-discussion statistics (e.g. post counts, mention counts, engagement figures) — not a store of raw Reddit content.

## What it is used for

Aggregate, derived statistics produced by this connector (e.g. mention counts and engagement metrics per stock ticker) are consumed by a separate, private, personal research application. That application's code is not part of this repository and is not public.

## Running it

Requires Perl 5.x with the core modules `HTTP::Tiny`, `JSON::PP`, and `MIME::Base64` (bundled with any standard modern Perl installation — no additional CPAN dependencies).

```
REDDIT_CLIENT_ID=... REDDIT_CLIENT_SECRET=... REDDIT_USER_AGENT="..." perl reddit_buzz_reader.pl
```

See `config.example` for the full list of environment variables and their purpose. Output is one JSON object per line (JSONL) on stdout.

## License

See repository owner for licensing terms.
