# Changelog

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
