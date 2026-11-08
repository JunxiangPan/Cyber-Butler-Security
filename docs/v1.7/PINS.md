# v1.7 Version Pins

Frozen minimums for the v1.7 release train:

```text
CBE  >= 0.1.0   (first version released through CBE/CBP)
CBP  >= 1.0.8   (minor pin)
CBS  == 1.7.0
CBM  == 0.x     (NOT_UPLOADED allowed)
CBC  == 0.x     (NOT_UPLOADED allowed)
```

Rules:

- Pin CBE/CBP at minor version; do not float to `main`.
- A breaking contract change requires one release cycle of notice and a
  CONTRACT version bump.
- `NOT_UPLOADED` never becomes PASS by pinning.
