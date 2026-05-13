# Security Policy

## Supported Versions

Security support applies to the latest signed beta release and the current
`main` branch. Older beta builds may be closed as unsupported unless the
maintainer states otherwise in the release notes.

## Reporting a Vulnerability

Do not include Codex auth payloads, API keys, refresh tokens, signing
credentials, private hostnames, or other secrets in public GitHub issues,
screenshots, logs, or attachments.

For vulnerabilities that can be reported without secrets, open a GitHub issue
with a minimal reproduction and clearly mark it as security-related.

For vulnerabilities that require private details, use the repository's GitHub
private vulnerability reporting or Security Advisory flow when it is available.

## Scope

In scope for the beta:

- local Codex auth snapshot handling;
- account switching and restoration behavior;
- remote-host snapshot install and switch flows;
- release artifact signing, notarization, and update packaging;
- accidental exposure of sensitive account, host, or signing data.

Out of scope:

- vulnerabilities in Codex itself or OpenAI services;
- issues requiring access to a reporter's private Codex account;
- social engineering, spam, or denial-of-service reports against public
  infrastructure;
- requests for a formal bug bounty or disclosure program.

## Handling Expectations

The maintainer will review credible beta security reports on a best-effort
basis, prioritize fixes that reduce risk to local auth state or release
integrity, and avoid asking reporters to share secrets when a sanitized
reproduction is enough.
