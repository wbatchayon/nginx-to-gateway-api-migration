# Contributing to NGINX to Gateway API Migration

Thank you for your interest in contributing!

## How to Contribute

### Reporting Bugs

1. Check existing issues
2. Create a new issue with detailed reproduction steps
3. Include version information

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Coding Standards

- Use 2 spaces for indentation in YAML
- Follow shell script best practices (use `set -euo pipefail`)
- Add comments to complex logic
- Test your changes locally

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yourfork/nginx-to-gateway-api-migration.git
cd nginx-to-gateway-api-migration

# Install development dependencies
pip install yamllint ansible-lint shellcheck

# Validate locally
make validate
```

### Testing

Before submitting a PR, ensure:

```bash
# Lint YAML files
yamllint kubernetes/ ansible/

# Check shell scripts
shellcheck scripts/*.sh

# Run smoke tests
./tests/smoke-tests.sh
```

## Code of Conduct

Please be respectful and inclusive. We follow the CNCF Code of Conduct.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
