# Security

The canonical security documentation is:

- [Defense layers](docs/10-security/defense-layers.md)
- [SCM service hardening](docs/10-security/scm-service-hardening.md)
- [WFP network policy](docs/10-security/wfp-network-policy.md)
- [Known limitations](docs/10-security/known-limitations.md)

AstrBot runs as the SCM service `CyberButlerAstrBot` under `CyberButlerSvc`; S4U scheduled tasks are retired. WFP is audit-only in v1.6.2-rc2.
