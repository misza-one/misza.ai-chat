# Security Policy

This Omarchy plugin runs inside `omarchy-shell` and is not sandboxed. Review the
source before enabling it, especially MCP server configuration.

Do not commit API keys, OAuth tokens or local chat history. API keys are stored in
the system keyring, and OpenCode-compatible OAuth tokens live outside this repo.

Report security issues privately through GitHub security advisories when
available, or by opening an issue without posting secrets.
