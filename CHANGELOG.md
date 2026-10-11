# Changelog

## 0.1.9

- `offset` is supported for pagination (`limit` plus `offset` must stay within turbopuffer's 10,000 maximum); counting a limited or offset relation raises `NotImplementedError` instead of a raw visitor error
- Requires the turbopuffer gem 2.5 or newer

## 0.1.8

- Namespace per tenant: `Document.namespace("documents-42")` scopes reads, writes, `update_all`, `delete_all` and `insert_all` to that namespace; records remember their namespace so `save`, `update!`, `reload` and `destroy` use it

## 0.1.7

- Server-side embeddings: `turbopuffer_attribute "body", "string", embed: "openai/text-embedding-3-small"` has turbopuffer embed the text on write, and `rank_by("body", "ANN", ["Embed", "query text"])` searches it by meaning

## 0.1.6

- Vector attributes are no longer loaded by default; `Document.with_vectors` (or an explicit `select` / `pluck`) fetches them. Reading an unloaded vector raises `ActiveModel::MissingAttributeError`

## 0.1.5

- `bytes` attributes (base64 on the wire, binary strings in Ruby), `[N]i8` integer vectors, and `{}f16` sparse vectors (declared with `sparse_knn` automatically)

## 0.1.4

- Turbopuffer errors are raised as ActiveRecord exceptions: `ConnectionFailed` and `StatementTimeout` for connection problems, `DatabaseConnectionError` for an invalid API key, and `StatementInvalid` (with the API error as `cause`) for everything else

## 0.1.3

- Consistency control: `Document.consistency(:eventual)` per query, `turbopuffer_consistency "eventual"` per model, or `consistency: eventual` in `database.yml`; query overrides model overrides connection, and turbopuffer's default (`strong`) applies when none is set

## 0.1.2

- Less-than and range filters no longer match documents that are missing the attribute, matching SQL semantics (turbopuffer's `Lt` / `Lte` match missing attributes by default)

## 0.1.1

- Gem summary and description state that the adapter is unofficial

## 0.1.0

Initial release.

- ActiveRecord adapter for turbopuffer: `adapter: turbopuffer` in `database.yml`
- `turbopuffer_attribute` schema DSL with `filterable`, `full_text_search`, `ann`, `glob` and `regex` options
- `turbopuffer_distance_metric` per namespace, defaulting to `cosine_distance`
- Type casting for `string`, `uuid`, `int`, `uint`, `float`, `bool`, `datetime`, array types and `[N]f32` / `[N]f16` vectors
- `where` filters including ranges, `nil`, regexp and glob patterns, and array containment
- `rank_by` for ANN and BM25 ranking
- `count`, `count(:column)`, `sum` and grouped aggregates
- `insert_all` / `upsert_all` batched into a single write, with generated UUIDv7 ids
- `update_all` and `delete_all` over turbopuffer's per-request limits
