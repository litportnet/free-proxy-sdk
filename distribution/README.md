# Distribution exports

These files prepare fixed, historical exports from an already downloaded, consistent `all.json` and `stats.json` pair. The generator does not call the API or a database.

```sh
node scripts/prepare-distribution.mjs \
  --source-dir /path/to/downloaded/proxies \
  --output /tmp/free-proxy-export \
  --owner litportnet \
  --source-commit 0123456789abcdef0123456789abcdef01234567
```

Upload `/tmp/free-proxy-export/huggingface/` by itself to Hugging Face. Upload `/tmp/free-proxy-export/kaggle-dataset/` as the Kaggle dataset, then upload `/tmp/free-proxy-export/kaggle-notebook/` separately as its notebook. Do not mix the Kaggle metadata or notebook with the Hugging Face upload.

Each dataset directory contains `all.json`, `all.csv`, `schema.json`, `LICENSE`, and `provenance.json`. The exported snapshot is historical, not a live service, and never displays a freshness badge.

`postman/collection.json` is ready to import without authentication. It contains only public Litport API requests and reserved documentation IPs in saved examples.
