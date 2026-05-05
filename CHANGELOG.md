# Changelog

## [0.3.0](https://github.com/alvera-ai/alvera-agent/compare/v0.2.0...v0.3.0) (2026-04-30)


### Features

* add domain-first skills (healthcare + AR/PR stubs) pinned to SDK 0.7.2 ([b646a93](https://github.com/alvera-ai/alvera-agent/commit/b646a93c85d18a3956b856bff4065f42153cacca))
* add domain-first skills (healthcare + AR/PR stubs) pinned to SDK 0.7.2 ([a09766d](https://github.com/alvera-ai/alvera-agent/commit/a09766d8050fe293c9ea03971ffd51d6f1ac692e))

## [0.2.0](https://github.com/alvera-ai/alvera-agent/compare/v0.1.0...v0.2.0) (2026-04-29)


### Features

* add agentic-workflow-creation skill with production templates ([d8afa1c](https://github.com/alvera-ai/alvera-agent/commit/d8afa1cce9955a2432ee15ff219e4ba182d83793))
* add isolated Claude Code sandbox script and update local settings with expanded bash command permissions ([2eb8f3e](https://github.com/alvera-ai/alvera-agent/commit/2eb8f3e09e66fa3319b7e2016f8fde82e0361ecf))
* add optional PostgREST explorer app scaffolding to custom dataset creation skill ([b89febb](https://github.com/alvera-ai/alvera-agent/commit/b89febbd2b3449ba462f0cd5c9672072208f763d))
* enable datalake creation within guided setup and improve sandbox environment isolation for testing ([baa0650](https://github.com/alvera-ai/alvera-agent/commit/baa0650265e797f61c9a433871dde47e9ab77d4e))
* enhance dataset creation to detect non-ISO date formats and flag them for auto-conversion in downstream interop templates ([c740bbb](https://github.com/alvera-ai/alvera-agent/commit/c740bbb823625b77c364e0d242a01482818e8ac0))
* **guided:** add agentic workflows, interop contracts, DAC CRUD ([6b0cea1](https://github.com/alvera-ai/alvera-agent/commit/6b0cea17471e78a32417c676c2df7b50d37d1f31))
* implement custom-dataset-creation skill and associated reference documentation ([a8a52d2](https://github.com/alvera-ai/alvera-agent/commit/a8a52d2a956c754e80814237eafef29659258547))
* **query-datasets:** add chat mode alongside React scaffold ([804425e](https://github.com/alvera-ai/alvera-agent/commit/804425e71e1678f8c88a3e914302bd85fe9ed4a6))
* **sandbox:** add activate.sh for multi-terminal sandbox sessions ([24d94ce](https://github.com/alvera-ai/alvera-agent/commit/24d94ce211ad6865d9c15960be7493c7c4dd3168))
* upgrade DAC-upload skill to an end-to-end ingestion pipeline with automated prerequisite resolution, data-quality scanning, and interop contract management. ([ebb386a](https://github.com/alvera-ai/alvera-agent/commit/ebb386a50f9d931b6b03ba8053a7e507e9daf29e))


### Bug Fixes

* align CLI cheatsheet and skill references with actual SDK cli.ts ([c4ce14f](https://github.com/alvera-ai/alvera-agent/commit/c4ce14f08c0cd72e47c1e7674add20a8588932f3))
* **custom-dataset-creation:** default ID-like integer columns to string ([ad50d25](https://github.com/alvera-ai/alvera-agent/commit/ad50d2585257a595d7738b681400462f5fe902d9))
* **sandbox:** zsh-safe activate.sh; proactive .env scaffolding for datalake creds ([cf4ae71](https://github.com/alvera-ai/alvera-agent/commit/cf4ae71f35670337970838f2a63a24be4910f296))
