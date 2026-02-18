# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability within this project, please send an email to the maintainers. All security vulnerabilities will be promptly addressed.

Please include the following information:

- Type of vulnerability
- Full paths of source file(s)
- Location of the affected source code
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue

## Security Considerations

### CVE-2025-1974 Mitigation

This project specifically addresses the CVE-2025-1974 vulnerability in NGINX Ingress Controller by migrating to Gateway API which eliminates the use of dangerous configuration snippets.

### Best Practices

1. **Never use NGINX Ingress snippets** - They can lead to RCE
2. **Use Gateway API CRDs** - Typed and validated
3. **Enable TLS everywhere** - Even internal traffic
4. **Follow RBAC principle** - Least privilege
5. **Use NetworkPolicies** - Segment your network

## Security Scanning

This project uses automated security scanning:

- Trivy for container/image scanning
- GitHub Advanced Security
- Dependabot for dependency updates
