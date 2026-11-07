# CBP Rule Packs

A pack is a JSON document with `name`, `version`, and `rules`.

```json
{
  "name": "cbp-pack-baseline",
  "version": "1.0.0",
  "rules": []
}
```

Reference it with an expected content hash:

```json
{
  "packs": [
    {
      "path": "rules/packs/cbp-pack-baseline@1.0.0.json",
      "sha256": "<sha256 of the pack file>"
    }
  ]
}
```

`extends` is recursive:

```json
{
  "extends": [
    {"path": "../base.json", "sha256": "<sha256>"}
  ],
  "rules": []
}
```

A hash mismatch, cycle, or malformed pack fails closed.
