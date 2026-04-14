# BoringCache Ruby

Prebuilt Ruby distributions cached in BoringCache.

Quick start:

```bash
curl -sSL https://install.boringcache.com/install.sh | sh
boringcache restore ruby/ruby ruby-3.4.9-yjit:/tmp/bc-ruby
export PATH="/tmp/bc-ruby/bin:$PATH"
ruby --version
```

Variants:

- `ruby-<version>` — standard
- `ruby-<version>-yjit`
- `ruby-<version>-jemalloc`
- `ruby-<version>-jemalloc-yjit`

GitHub Actions example:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      BORINGCACHE_RESTORE_TOKEN: ${{ secrets.BORINGCACHE_RESTORE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - run: |
          curl -sSL https://install.boringcache.com/install.sh | sh
          boringcache restore ruby/ruby ruby-3.4.9-yjit:./ruby
          echo "$PWD/ruby/bin" >> $GITHUB_PATH
```
