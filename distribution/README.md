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

## Published listings and updates

`listings.json` records verified public URLs, versions, observed link attributes and any blocked submission. Registry pages can help discovery, but publication does not guarantee search indexing or ranking.

GitHub Actions → **Publish distribution targets** supports manual JSR, Docker and Hugging Face publication from `main`. JSR and Hugging Face use trusted publishing. Docker builds an image artifact even without publishing secrets; adding `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` enables direct push. Choose a new image version before publishing another release; the workflow refuses to overwrite the initial tag. Go uses directory-prefixed tags such as `packages/go/v0.1.0`. Rust releases use Cargo and must pass tests on their declared minimum compiler.

Historical dataset uploads are explicit, dated releases rather than a scheduled live feed. Preserve the source commit and observation time when updating an existing listing. Kaggle notebooks read the exported CSV directly, with internet access disabled; they do not use the SDK's current-proxy freshness filter.
