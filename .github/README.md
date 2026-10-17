# GitHub repository automation

This directory configures GitHub-hosted maintenance and validation. It is not
part of the installed Skia API.

- [dependabot.yml](dependabot.yml) requests weekly GitHub Actions dependency
  updates, with at most five open update pull requests.
- [workflows/](workflows/README.md) contains automatic source/CPU/acceptance
  gates, opt-in feature checks, release-candidate checks, and manual documentation
  publication.

See [CI](../docs/CI.md) and [regression scope](../docs/CI-REGRESSION-SCOPE.md)
before changing which checks run automatically. A workflow definition describes
what can run; it is not evidence that a particular platform has passed.
