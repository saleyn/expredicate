# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-19

### Added

- Initial A-Tree implementation with NIF wrapper
- Core functionality:
  - Tree creation and management (`new/0`, `clear/1`, `empty/1`)
  - Pattern insertion (`insert/2`)
  - Exact pattern matching (`search/2`)
  - Prefix-based matching (`find_with_prefix/2`)
  - Substring-based matching (`find_containing/2`)
  - Tree introspection (`all_patterns/1`, `count/1`)
- Comprehensive test suite
- Documentation and examples
- Support for Erlang/OTP 24+

### Features

- High-performance C++ implementation of A-Tree data structure
- Seamless Elixir/NIF integration
- Thread-safe operations
- Minimal memory overhead
