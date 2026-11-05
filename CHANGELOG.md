## [Unreleased]

- Allow rubyzip 3.x (`>= 2.4, < 4`): rubyzip before 3.4.0 has a path traversal advisory (GHSA-47m2-wp7j-p9vc). The converter only reads entries in memory, so it is unaffected by the API change; tests pass on rubyzip 3.7.0.

## [0.1.0] - 2026-05-28

- Initial release
