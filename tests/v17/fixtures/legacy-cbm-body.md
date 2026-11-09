# cbm v0.1.0 — Release evidence

## Source excerpt (real CBM README)

# CBM attach evidence (v0.1.0)

[![cbm-ci](https://github.com/JunxiangPan/cbm/actions/workflows/ci.yml/badge.svg)](https://github.com/JunxiangPan/cbm/actions/workflows/ci.yml)

CBM is a **sidecar attachment attestation** for the v1.7 release train. It is
not the 10th traditional gate, it is not a CBP gate, and it is not in the CBS
`publish` `needs` graph. It consumes CBE/CBP reports that already exist and
decides whether the optional CBM build-once artifact may be attached.

The frozen F1-F6 source is `docs/v1.7/CONTRACT.md` in the CBS repository,
commit `4a437df`, SHA-256
`a561f19e0a8e4dba92af82400b5696da18e000ba5362571cb0b40243b9a3afca`.
CBM does not define a private variant of F1-F6.

During CBM v0.1.0 the CBS repository advanced past `eeb3645` and added an
additive §11 (build-once profiles); F1-F6 and §5 are unchanged. CBM's artifact

## Provenance

Assembled from CBM 8acb628.
