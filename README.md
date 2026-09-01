# AI Chat for Omarchy

AI Chat puts a capable, desktop-native AI assistant directly in your Omarchy bar.
Open it with a click or shortcut, choose a local or hosted model, attach files,
enable MCP tools, and keep the conversation flowing without leaving your desktop.

It is built for people who switch between local models, hosted endpoints, API
keys, browser-assisted sign-in flows, and tool-enabled workflows. The panel stays
fast, theme-aware, and close to Omarchy's own visual language.

## Features

- **Bar-native AI chat**: opens from the Omarchy bar as a floating, resizable chat window.
- **Local and hosted providers**: presets for OpenAI, xAI/Grok, Kimi/Moonshot, Z.ai/GLM, OpenRouter, Ollama, LM Studio, llama.cpp, vLLM, LocalAI, Jan, text-generation-webui, KoboldCpp, and custom OpenAI-compatible endpoints.
- **Per-provider memory**: endpoint and model choices are saved per provider, so switching between local servers and cloud accounts stays painless.
- **API key support**: provider keys are saved in the system keyring, not in plain text config files.
- **Browser-assisted auth where supported**: selected providers can open a browser flow; OpenAI and xAI can reuse OpenCode-compatible credentials, while OpenRouter stores a user-controlled API key in the keyring.
- **MCP tool discovery**: finds MCP servers from common OpenCode, Claude, Cursor, VS Code, Windsurf, Zed, and generic config locations.
- **Tool toggles in chat**: enable or disable discovered MCP servers from inside the chat panel and reload when ready.
- **Inline tool calls**: tool activity appears in the transcript and stays collapsed until you expand it.
- **Saved chats**: conversation history is stored locally and can be loaded, renamed, or deleted from the sidebar.
- **Searchable model picker**: filter long model lists directly from the dropdown.
- **File and media attachments**: attach image, video, audio, PDF, text, Markdown, JSON, CSV, YAML, and log files when the selected model supports them.
- **Markdown rendering**: AI responses render Markdown, including readable scrollable tables.
- **Streaming-friendly UI**: streaming text stays smooth while final messages get richer formatting.
- **Theme-aware design**: message cards, borders, chips, buttons, and status panels use Omarchy theme colors instead of hard-coded branding.
- **Desktop shortcuts**: works well with custom Hyprland bindings such as open and close shortcuts.

## Why Use It

- Use local Ollama or LM Studio models for private everyday prompts.
- Switch to OpenAI, Grok, OpenRouter, or another compatible endpoint when you want hosted models.
- Bring existing MCP tools into the same desktop chat without manually wiring every server.
- Keep chats, attachments, tools, and model selection in one Omarchy-native interface.
- Avoid pasting API keys into shell config or random scripts.

## Install

```sh
omarchy plugin add https://github.com/misza-one/misza.ai-chat.git --enable
```

After installation, add the widget to your bar if Omarchy does not place it
automatically. Open the panel, choose a provider, connect or sign in, select a
model, and start chatting.

## Shortcuts

The plugin can be summoned or hidden from Hyprland bindings:

```sh
omarchy-shell shell summon misza.ai-chat '{}'
omarchy-shell shell hide misza.ai-chat
```

Example Omarchy Hyprland bindings:

```lua
o.bind("SUPER + CTRL + UP", "AI Chat", "omarchy-shell shell summon misza.ai-chat '{}'")
o.bind("SUPER + CTRL + DOWN", "Close AI Chat", "omarchy-shell shell hide misza.ai-chat")
```

## Data And Privacy

- Chats are stored locally under `~/.local/state/misza.ai-chat/`.
- API keys are stored in the system keyring.
- OpenCode-compatible OAuth tokens are used only for providers that explicitly support that flow, currently OpenAI and xAI.
- OpenRouter's browser flow saves an API key in the system keyring.
- The plugin runs inside `omarchy-shell`, like other Omarchy shell plugins.
- Provider requests are sent only to the endpoint/account you configure.

## MCP Tools

AI Chat can auto-discover MCP servers from common desktop AI tool configs. Open
the Tools panel in chat to review what was found, toggle servers, rescan configs,
and reload the connection when your selection changes.

Use `mcp.example.json` as a starting point if you want a small standalone MCP
configuration for local testing.

## Remove

```sh
omarchy plugin remove misza.ai-chat
```
