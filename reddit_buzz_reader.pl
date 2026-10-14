#!/usr/bin/perl

# Read-only Reddit Data API connector.
#
# Authenticates via OAuth2 client_credentials grant (anonymous,
# unprivileged, app-only access - no Reddit user login is required or
# used), then fetches the newest public posts from a small, fixed list
# of finance-related subreddits and emits a minimal, structured JSONL
# record per post. Performs GET requests only - no posting, voting,
# messaging, or moderation action of any kind.
#
# Credentials are read from environment variables only. See
# config.example for the required variable names. Nothing in this
# script performs any write action against Reddit.

use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP qw(decode_json);
use MIME::Base64 qw(encode_base64);

# Small, fixed list of finance-related subreddits. Intentionally not
# configurable via 503-symbol-style per-ticker queries - this reads a
# handful of community streams, not a per-symbol search.
my @SUBREDDITS = qw(stocks investing wallstreetbets);

my $TOKEN_URL     = "https://www.reddit.com/api/v1/access_token";
my $API_BASE      = "https://oauth.reddit.com";
my $POSTS_PER_PAGE = 100;
my $MAX_PAGES_PER_SUBREDDIT = 1; # bounded single-run PoC, not a continuous crawl

my $client_id     = $ENV{REDDIT_CLIENT_ID}
    or die "Missing required environment variable: REDDIT_CLIENT_ID\n";
my $client_secret = $ENV{REDDIT_CLIENT_SECRET}
    or die "Missing required environment variable: REDDIT_CLIENT_SECRET\n";
my $user_agent     = $ENV{REDDIT_USER_AGENT}
    or die "Missing required environment variable: REDDIT_USER_AGENT "
          . "(Reddit requires a descriptive User-Agent identifying the app)\n";

# Optional, off by default: fetching public comments for each post.
# Disabled unless explicitly requested - the core post-reading path
# never depends on this.
my $include_comments = $ENV{REDDIT_INCLUDE_COMMENTS} ? 1 : 0;

my $http = HTTP::Tiny->new(
    agent   => $user_agent,
    timeout => 20,
);

sub get_access_token
{
    my $auth = encode_base64("$client_id:$client_secret", '');

    my $response = $http->post_form(
        $TOKEN_URL,
        { grant_type => "client_credentials" },
        {
            headers => {
                "Authorization" => "Basic $auth",
                "User-Agent"    => $user_agent,
            },
        }
    );

    if (!$response->{success})
    {
        die "Failed to obtain Reddit access token: HTTP $response->{status} "
            . "$response->{reason}\n$response->{content}\n";
    }

    my $token_data = decode_json($response->{content});

    if (!defined $token_data->{access_token})
    {
        die "Reddit token response did not contain an access_token:\n"
            . "$response->{content}\n";
    }

    return {
        access_token => $token_data->{access_token},
        expires_at   => time() + ($token_data->{expires_in} // 3600) - 30,
    };
}

sub respect_rate_limit
{
    my ($response) = @_;

    if ($response->{status} == 429)
    {
        my $retry_after = $response->{headers}{"retry-after"} // 5;
        warn "Rate limited (HTTP 429), sleeping $retry_after seconds before retry\n";
        sleep($retry_after);
        return 1; # caller should retry
    }

    my $remaining = $response->{headers}{"x-ratelimit-remaining"};

    if (defined $remaining && $remaining < 2)
    {
        my $reset = $response->{headers}{"x-ratelimit-reset"} // 5;
        warn "Rate limit nearly exhausted (remaining=$remaining), "
            . "sleeping $reset seconds\n";
        sleep($reset);
    }

    return 0;
}

sub fetch_subreddit_new
{
    my ($token, $subreddit) = @_;

    my @posts;
    my $after;
    my $pages_fetched = 0;

    while ($pages_fetched < $MAX_PAGES_PER_SUBREDDIT)
    {
        my $url = "$API_BASE/r/$subreddit/new.json?limit=$POSTS_PER_PAGE";
        $url .= "&after=$after" if defined $after;

        my $response;
        my $attempts = 0;

        while (1)
        {
            $attempts++;
            $response = $http->get(
                $url,
                {
                    headers => {
                        "Authorization" => "bearer $token",
                        "User-Agent"    => $user_agent,
                    },
                }
            );

            last if $response->{success};

            if ($attempts < 3 && respect_rate_limit($response))
            {
                next;
            }

            warn "Failed to fetch r/$subreddit: HTTP $response->{status} "
                . "$response->{reason}\n";
            return @posts;
        }

        my $data = decode_json($response->{content});
        my $children = $data->{data}{children} // [];

        last if !@$children;

        push @posts, @$children;

        $after = $data->{data}{after};
        $pages_fetched++;

        last if !defined $after;
    }

    return @posts;
}

sub extract_cashtags
{
    my ($text) = @_;

    my %seen;
    while ($text =~ /\$([A-Za-z]{1,6})\b/g)
    {
        $seen{uc($1)} = 1;
    }

    return sort keys %seen;
}

sub fetch_comments_for_post
{
    # Optional, disabled by default (REDDIT_INCLUDE_COMMENTS). Reads
    # public comments for a single post. Same read-only, no-write
    # contract as post fetching.
    my ($token, $subreddit, $post_id) = @_;

    my $url = "$API_BASE/r/$subreddit/comments/$post_id.json?limit=50";

    my $response = $http->get(
        $url,
        {
            headers => {
                "Authorization" => "bearer $token",
                "User-Agent"    => $user_agent,
            },
        }
    );

    return [] if !$response->{success};

    my $data = decode_json($response->{content});
    my $comment_listing = $data->[1]{data}{children} // [];

    my @comments;

    for my $child (@$comment_listing)
    {
        next if ($child->{kind} // '') ne 't1';

        my $c = $child->{data};
        my $body = $c->{body} // '';

        push @comments, {
            comment_id => $c->{id},
            created_utc => $c->{created_utc},
            score      => $c->{score},
            cashtags   => [ extract_cashtags($body) ],
        };
    }

    return \@comments;
}

# --- main ---

my $token_info = get_access_token();
my $token = $token_info->{access_token};

for my $subreddit (@SUBREDDITS)
{
    if (time() >= $token_info->{expires_at})
    {
        $token_info = get_access_token();
        $token = $token_info->{access_token};
    }

    my @children = fetch_subreddit_new($token, $subreddit);

    for my $child (@children)
    {
        next if ($child->{kind} // '') ne 't3';

        my $post = $child->{data};

        # Title/selftext are read only in memory to extract cashtags,
        # then discarded - raw post text is not part of the output.
        my $combined_text = ($post->{title} // '') . " " . ($post->{selftext} // '');
        my @cashtags = extract_cashtags($combined_text);

        my %record = (
            subreddit     => $subreddit,
            post_id       => $post->{id},
            created_utc   => $post->{created_utc},
            score         => $post->{score},
            num_comments  => $post->{num_comments},
            cashtags      => \@cashtags,
            permalink     => "https://www.reddit.com" . ($post->{permalink} // ''),
        );

        if ($include_comments)
        {
            $record{comments} = fetch_comments_for_post($token, $subreddit, $post->{id});
        }

        print encode_json_line(\%record), "\n";
    }
}

sub encode_json_line
{
    my ($record) = @_;
    my $json = JSON::PP->new->canonical->utf8;
    return $json->encode($record);
}
