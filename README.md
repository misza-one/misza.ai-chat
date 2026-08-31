# AI Chat

Omarchy bar chat for OpenAI-compatible endpoints. Built-in presets cover OpenAI,
xAI/Grok, Kimi/Moonshot, Z.ai/GLM, OpenRouter, Ollama, LM Studio, llama.cpp,
vLLM, LocalAI, Jan, text-generation-webui, KoboldCpp and custom endpoints. Local
endpoint edits are saved per provider, so switching away from a local server and
back restores its last URL.

API keys are stored in the system keyring. Plan logins reuse the same real flows
as OpenCode where available: OpenAI uses the ChatGPT Pro/Plus browser OAuth
callback, xAI uses the SuperGrok device OAuth flow, and both are saved in
OpenCode-compatible `~/.local/share/opencode/auth.json`. OpenRouter uses its
documented PKCE flow and stores the returned user-controlled API key in the
keyring. API key pages are not treated as OAuth.

The panel auto-discovers MCP servers from common OpenCode, Claude, Cursor, VS
Code, Windsurf, Zed and generic config paths, then lets you toggle individual
servers. Chats are saved under `~/.local/state/misza.ai-chat/`. Tool calls are
displayed inline, and the composer accepts image, video, audio and file paths or
URLs when the selected model/provider supports multimodal chat completions.

## Install

```sh
omarchy plugin add https://github.com/miszarchy/misza.ai-chat.git --enable
```

## Remove

```sh
omarchy plugin remove misza.ai-chat
```
