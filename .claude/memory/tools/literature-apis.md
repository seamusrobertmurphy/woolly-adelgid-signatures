# Literature search APIs: what works here and what does not

2026-08-14: OpenAlex free tier is metered at 1000 requests or 0.10 USD per day, resetting
at midnight UTC, and paging two broad queries to exhaustion spends it. Matters because
exhausting it blocks the review for 20 hours; check `x-ratelimit-remaining` before any
bulk run. Rests on the 429 body observed in commit `e190570`.

2026-08-14: Semantic Scholar's `paper/search/bulk` endpoint is the better index for this
domain: Boolean syntax with `+` AND, `|` OR, `-` NOT, matching on title and abstract,
complete result sets. OpenAlex reported 5387 matches on the bare adelgid concept where
Semantic Scholar reports 46. Its plain `paper/search` endpoint throttles hard while bulk
does not. Rests on `05.scripts/08-review-search-s2.py`.

2026-08-14: Semantic Scholar returns **no abstracts** for Elsevier and IEEE records, which
carry a publisher elision notice instead. Crossref supplied 12 abstracts of 251 DOIs
tried, Europe PMC 30. Matters because abstract-based screening silently fails on exactly
the journals this field publishes in, and 2820 of 5663 records in this review have no
abstract from any source.

2026-08-14: NASA ADS is the only available cited-reference search, through
`citations(doi:...)` and `references(doi:...)`, which is the Web of Science capability
this project cannot otherwise reach. Token at `~/.ads/dev_key`, 5000 queries per day
shared with `forest-fire-index-trends`. Matters because forward chasing from a seed paper
is the most reliable way to find work that supersedes it. Rests on
`05.scripts/11-ads-search.py`.

2026-08-14: ADS silently collapses some tokens to zero hits, so every content word must be
tested individually before it enters a search string, and Boolean set identities checked.
Both were verified for this project and no intended token collapsed. Matters because a
query built on a collapsed token returns a large, plausible, irrelevant set. Recorded in
the protocol under deviations.

2026-08-14: Google Scholar is not usable. No public API, terms prohibit automated access,
and scraped results are not reproducible by a referee. Web of Science needs a Clarivate
key that does not exist on this machine; the free trial tier is open to anyone but is
capped at 50 requests a day and returns no citation counts.
