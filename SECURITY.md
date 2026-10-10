# Security Policy

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability** (GitHub private security advisories): https://github.com/Etienne-Morax/morax-garage/security/advisories/new

Do not open a public issue for security problems. Include the affected version, steps to reproduce and the impact. You will get an acknowledgement within a few days, and credit in the release notes if you want it.

## Scope

Of particular interest: anything that makes the cleanup engine delete or move data outside what `SafetyGate` allows (path traversal, symlink escapes, protected-path bypass), leaks of API keys stored in the Keychain, and unsafe handling of the network endpoints described in the README's Privacy section.

Releases are currently ad-hoc signed and not notarized. See the README for first-launch instructions.
