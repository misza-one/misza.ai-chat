import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "misza.ai-chat"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string bridgePath: Qt.resolvedUrl("bin/ai-chat-bridge").toString().replace("file://", "")
  readonly property string omarchyLogoSource: "file:///usr/share/omarchy/logo.svg"

  property bool connected: false
  property bool settingsOpen: false
  property bool advancedOpen: false
  property bool chatSidebarOpen: false
  property bool chatToolsOpen: false
  property bool drawerOpen: false
  property bool sending: false
  property string errorText: ""
  property var errorDebug: null
  property bool debugOpen: false
  property bool retryAvailable: false
  property string retryNotice: ""
  property string activityText: ""
  property string providerId: String(setting("providerId", "ollama"))
  property string authMode: String(setting("authMode", "none"))
  property string selectedModel: String(setting("model", ""))
  property string thinkingLevel: String(setting("thinkingLevel", ""))
  property string endpointDraft: String(setting("baseUrl", ""))
  property string activeProviderId: ""
  property string activeAuthMode: ""
  property string activeBaseUrl: ""
  property string activeMcpEnabled: ""
  property string currentChatId: ""
  property string renamingChatId: ""
  property string renameDraft: ""
  property var providers: []
  property var models: []
  property var modelByProvider: parseJsonObject(setting("modelByProvider", "{}"))
  property var endpointByProvider: parseJsonObject(setting("endpointByProvider", "{}"))
  property var mcpConfigs: []
  property var allMcpServers: []
  property var mcpServers: []
  property var enabledMcpKeys: parseJsonArray(setting("mcpEnabled", "[]"))
  property var chats: []
  property var messages: []
  property var attachments: []
  property int assistantDraftIndex: -1
  property string assistantTargetText: ""
  property string assistantVisibleText: ""
  property bool assistantDraftStreaming: false
  readonly property color aiAccent: Color.accent
  readonly property color userAccent: Color.popups.text
  readonly property color toolAccent: Color.muted

  readonly property string configuredBaseUrl: String(setting("baseUrl", ""))
  readonly property string configuredMcpPath: String(setting("mcpPath", ""))
  readonly property var modelOptions: models.map(function(model) {
    return { value: model.id, label: model.label, description: model.description || "" }
  })
  readonly property var providerOptions: providers.map(function(provider) {
    return { value: provider.id, label: provider.label }
  })
  readonly property var authModeOptions: authOptionsForProvider()
  readonly property var thinkingModeOptions: thinkingOptionsForSelectedModel()
  readonly property bool ready: connected && activeProviderId === providerId && activeAuthMode === authMode
    && activeBaseUrl === endpointDraft.trim() && activeMcpEnabled === JSON.stringify(enabledMcpKeys)

  function parseJsonArray(value) {
    if (Array.isArray(value)) return value.slice()
    try {
      var parsed = JSON.parse(String(value || "[]"))
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      return []
    }
  }

  function parseJsonObject(value) {
    if (value && typeof value === "object" && !Array.isArray(value)) return value
    try {
      var parsed = JSON.parse(String(value || "{}"))
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    } catch (e) {
      return {}
    }
  }

  function statusText() {
    if (activityText !== "") return activityText
    if (retryNotice !== "") return retryNotice
    if (!ready) return connected ? "Changes not loaded" : "Not connected"
    var suffix = models.length === 1 ? " model" : " models"
    var toolCount = activeMcpCount()
    return "Connected / " + models.length + suffix + (toolCount > 0 ? " / " + toolCount + " MCP" : "")
  }

  function persistSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings)
      if (key !== "id") entry[key] = root.settings[key]
    for (var changed in patch) entry[changed] = patch[changed]
    root.settings = entry
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function currentProvider() {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].id === providerId) return providers[i]
    return { id: providerId, label: providerId || "Custom", baseUrl: configuredBaseUrl,
      authModes: ["none", "key", "oauth"], defaultAuthMode: authMode || "key", keyUrl: "", oauth: {} }
  }

  function currentProviderLabel() {
    return currentProvider().label || providerId || "Custom"
  }

  function currentProviderAuthStatus() {
    return currentProvider().authStatus || "unknown"
  }

  function providerOAuthKind(provider) {
    var oauth = (provider && typeof provider.oauth === "object") ? provider.oauth : {}
    return String(oauth.kind || "")
  }

  function oauthOptionLabel(provider) {
    var kind = providerOAuthKind(provider)
    if (kind === "openrouter") return "Browser API key"
    if (kind.indexOf("opencode-") === 0) return "OpenCode login"
    return "Browser login"
  }

  function authOptionsForProvider() {
    var provider = currentProvider()
    var labels = { none: "Local / no login", key: "API key" }
    var modes = provider.authModes || ["key"]
    var out = []
    for (var i = 0; i < modes.length; i++) {
      var mode = String(modes[i])
      out.push({ value: mode, label: mode === "oauth" ? oauthOptionLabel(provider) : (labels[mode] || mode) })
    }
    return out
  }

  function authModeLabel() {
    var labels = { none: "Local", key: "API key", oauth: oauthOptionLabel(currentProvider()) }
    return labels[authMode] || authMode
  }

  function authModeDescription(mode) {
    if (mode === "oauth" && providerOAuthKind(currentProvider()) === "openrouter") return "Create an OpenRouter API key in the browser and save it in the keyring"
    if (mode === "oauth") return "Use a supported browser login when available"
    if (mode === "key") return "Use a token saved in the system keyring"
    if (mode === "none") return "Use a local OpenAI-compatible endpoint"
    return String(mode)
  }

  function connectionHelpText() {
    if (ready) return "Ready. Switch to chat when you are done adjusting tools."
    if (connected) return "Load models again to apply the changed account, endpoint or tools."
    if (authMode === "oauth") return oauthDescription()
    if (authMode === "key") {
      if (methodStatusText() === "API key saved") return "Key found in the system keyring. Load models to continue."
      return "Paste an API key once. It is saved in the system keyring, not shell.json."
    }
    if (endpointDraft.trim() === "") return "Enter a local OpenAI-compatible endpoint."
    return "No login needed. Connect to load models from the local endpoint."
  }

  function selectedModelInfo() {
    for (var i = 0; i < models.length; i++)
      if (models[i].id === selectedModel) return models[i]
    return null
  }

  function modelCapabilitiesText() {
    var info = selectedModelInfo()
    var caps = info ? (info.capabilities || {}) : {}
    var parts = []
    if (caps.toolCalls) parts.push("tools")
    if (thinkingModeOptions.length > 0) parts.push("thinking")
    if (caps.image) parts.push("image")
    if (caps.video) parts.push("video")
    if (caps.audio) parts.push("audio")
    if (caps.files) parts.push("files")
    return parts.length > 0 ? parts.join(" / ") : "unknown capabilities"
  }

  function thinkingOptionValue(option) {
    return option && typeof option === "object" ? String(option.value) : String(option)
  }

  function thinkingOptionLabel(option) {
    return option && typeof option === "object" ? String(option.label) : String(option)
  }

  function thinkingOptionsForSelectedModel() {
    var info = selectedModelInfo()
    var caps = info ? (info.capabilities || {}) : {}
    var levels = caps.thinkingLevels || []
    return Array.isArray(levels) ? levels : []
  }

  function thinkingLabel() {
    if (thinkingModeOptions.length === 0) return ""
    for (var i = 0; i < thinkingModeOptions.length; i++) {
      var option = thinkingModeOptions[i]
      if (thinkingOptionValue(option) === thinkingLevel) return thinkingOptionLabel(option)
    }
    return thinkingOptionLabel(thinkingModeOptions[0])
  }

  function normalizeThinkingLevel() {
    if (models.length === 0 && selectedModel !== "") return
    if (thinkingModeOptions.length === 0) {
      if (thinkingLevel !== "") {
        thinkingLevel = ""
        persistSettings({ thinkingLevel: "" })
        bridge.send({ op: "thinking", thinkingLevel: "" })
      }
      return
    }
    for (var i = 0; i < thinkingModeOptions.length; i++)
      if (thinkingOptionValue(thinkingModeOptions[i]) === thinkingLevel) return
    setThinkingLevel(thinkingOptionValue(thinkingModeOptions[0]))
  }

  function chatCapabilityChips() {
    var info = selectedModelInfo()
    var caps = info ? (info.capabilities || {}) : {}
    var parts = []
    if (selectedModel !== "") parts.push("Model: " + selectedModel)
    if (thinkingModeOptions.length > 0) parts.push("Thinking: " + thinkingLabel())
    if (caps.toolCalls) parts.push(activeMcpCount() > 0 ? "Tools: " + activeMcpCount() : "Tools capable")
    if (caps.image) parts.push("Images")
    if (caps.video) parts.push("Video")
    if (caps.audio) parts.push("Audio")
    if (caps.files) parts.push("Files")
    return parts.length > 0 ? parts : ["Capabilities unknown"]
  }

  function modelConfigKey() {
    return providerId + "\n" + authMode + "\n" + endpointDraft.trim()
  }

  function endpointForProvider(id) {
    return String(endpointByProvider[id] || "")
  }

  function defaultEndpointForProvider(id) {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].id === id) return providers[i].baseUrl || ""
    return id === providerId ? currentProvider().baseUrl || "" : ""
  }

  function effectiveEndpointForProvider(id) {
    return endpointForProvider(id) || defaultEndpointForProvider(id)
  }

  function endpointStoreWith(id, value) {
    var next = {}
    for (var key in endpointByProvider) next[key] = endpointByProvider[key]
    if (value !== "") next[id] = value
    return next
  }

  function persistEndpointForProvider(id, value) {
    if (!id || value === "") return endpointByProvider
    var next = endpointStoreWith(id, value)
    endpointByProvider = next
    persistSettings({ endpointByProvider: JSON.stringify(next) })
    return next
  }

  function storedModelForCurrentConfig() {
    return String(modelByProvider[modelConfigKey()] || modelByProvider[providerId] || "")
  }

  function modelStoreWith(value) {
    var next = {}
    for (var key in modelByProvider) next[key] = modelByProvider[key]
    if (value !== "") {
      next[modelConfigKey()] = value
      next[providerId] = value
    }
    return next
  }

  function persistSelectedModel(value) {
    var next = modelStoreWith(value)
    modelByProvider = next
    persistSettings({ model: value, modelByProvider: JSON.stringify(next) })
  }

  function setSelectedModel(value, notifyBridge) {
    selectedModel = value
    persistSelectedModel(value)
    normalizeThinkingLevel()
    if (notifyBridge) bridge.send({ op: "model", model: value })
  }

  function setThinkingLevel(value) {
    thinkingLevel = value
    persistSettings({ thinkingLevel: value })
    bridge.send({ op: "thinking", thinkingLevel: value })
  }

  function activeConnectionText() {
    if (ready)
      return currentProviderLabel() + " is ready"
    if (connected) return "Changes not loaded"
    if (activityText !== "") return activityText
    return "Choose an account to start."
  }

  function activeConnectionDetail() {
    var detail = authModeLabel() + " / " + methodStatusText()
    if (ready) detail += " / " + (selectedModel || "no model")
    else if (connected) detail += " / click Load models to apply"
    return detail
  }

  function methodStatusText() {
    var status = currentProviderAuthStatus()
    if (authMode === "none") return "No login needed"
    if (authMode === "oauth") {
      if (providerOAuthKind(currentProvider()) === "openrouter")
        return status.indexOf("saved") >= 0 ? "API key saved" : "API key missing"
      if (status.indexOf("signed in") >= 0 || status.indexOf("saved") >= 0) return "Login connected"
      return "Not logged in"
    }
    if (authMode === "key") {
      if (status.indexOf("API key saved") >= 0 || status.indexOf("Browser key saved") >= 0) return "API key saved"
      return "API key missing"
    }
    return status
  }

  function authReady() {
    var status = methodStatusText()
    return status === "Login connected" || status === "API key saved" || status === "No login needed"
  }

  function mainActionText() {
    if (authMode === "oauth") return authReady() ? (ready ? "Reload models" : "Load models") : (providerOAuthKind(currentProvider()) === "openrouter" ? "Create key" : "Sign in")
    if (authMode === "key") return methodStatusText() === "API key saved" ? (ready ? "Reload models" : "Load models") : "Save key first"
    return ready ? "Reconnect" : "Connect"
  }

  function runMainAction() {
    if (authMode === "oauth" && !authReady()) startOAuth()
    else connect()
  }

  function clearLoadedModels() {
    models = []
    mcpServers = []
  }

  function providerRowDescription(provider) {
    var status = provider.authStatus || "unknown"
    var mode = provider.defaultAuthMode === "oauth" ? oauthOptionLabel(provider) : (provider.defaultAuthMode === "none" ? "No auth" : "API key")
    var endpoint = provider.id === providerId ? endpointDraft.trim() : effectiveEndpointForProvider(provider.id)
    return mode + " / " + status + (endpoint ? " / " + endpoint : "")
  }

  function normalizeAuthMode() {
    var provider = currentProvider()
    var modes = provider.authModes || ["key"]
    if (modes.indexOf(authMode) >= 0) return
    authMode = provider.defaultAuthMode || modes[0]
    persistSettings({ authMode: authMode })
  }

  function selectProvider(value) {
    if (providerId !== value) {
      persistEndpointForProvider(providerId, endpointField.text.trim())
      if (selectedModel !== "") persistSelectedModel(selectedModel)
      clearLoadedModels()
    }
    providerId = value
    var provider = currentProvider()
    var endpoint = effectiveEndpointForProvider(providerId)
    endpointDraft = endpoint
    endpointField.text = endpoint
    var modes = provider.authModes || ["key"]
    if (modes.indexOf(authMode) < 0) authMode = provider.defaultAuthMode || modes[0]
    selectedModel = storedModelForCurrentConfig()
    persistSettings({ providerId: providerId, authMode: authMode, baseUrl: endpoint,
      model: selectedModel, endpointByProvider: JSON.stringify(endpointByProvider) })
  }

  function selectAuthMode(value) {
    persistEndpointForProvider(providerId, endpointField.text.trim())
    if (authMode !== value && selectedModel !== "") persistSelectedModel(selectedModel)
    if (authMode !== value) clearLoadedModels()
    authMode = value
    selectedModel = storedModelForCurrentConfig()
    persistSettings({ authMode: value, baseUrl: endpointField.text.trim(), model: selectedModel,
      endpointByProvider: JSON.stringify(endpointByProvider) })
  }

  function providerOAuth() {
    var provider = currentProvider()
    return provider.oauth || {}
  }

  function hasProviderOAuth() {
    var oauth = providerOAuth()
    return oauth.kind !== undefined && oauth.kind !== ""
  }

  function oauthDescription() {
    var kind = providerOAuth().kind || ""
    if (kind === "opencode-openai")
      return "Uses an OpenCode-compatible OpenAI browser login. The token is saved for OpenCode and this widget."
    if (kind === "opencode-xai")
      return "Uses an OpenCode-compatible xAI browser login. The returned token is saved for OpenCode and this widget."
    if (kind === "openrouter")
      return "Opens OpenRouter in the browser to create a user-controlled API key, then saves that key in the system keyring."
    return "This provider does not expose a built-in browser auth flow here. Use API key mode."
  }

  function connect() {
    var baseUrl = endpointField.text.trim()
    var mcpPath = mcpPathField.text.trim()
    endpointDraft = baseUrl
    var endpointStore = persistEndpointForProvider(providerId, baseUrl)
    if (selectedModel === "") selectedModel = storedModelForCurrentConfig()
    normalizeThinkingLevel()
    var modelStore = modelStoreWith(selectedModel)
    modelByProvider = modelStore
    activityText = "Connecting " + currentProviderLabel() + "..."
    clearErrorState()
    persistSettings({ providerId: providerId, authMode: authMode, baseUrl: baseUrl,
      endpointByProvider: JSON.stringify(endpointStore), model: selectedModel,
      modelByProvider: JSON.stringify(modelStore), thinkingLevel: thinkingLevel,
      mcpPath: mcpPath, mcpEnabled: JSON.stringify(enabledMcpKeys) })
    bridge.send({ op: "configure", providerId: providerId, authMode: authMode, baseUrl: baseUrl,
      model: selectedModel, thinkingLevel: thinkingLevel, mcpPath: mcpPath, mcpEnabled: enabledMcpKeys })
  }

  function saveApiKey() {
    var key = apiKeyField.text
    if (key === "" || authMode === "none") return
    var baseUrl = endpointField.text.trim()
    endpointDraft = baseUrl
    var endpointStore = persistEndpointForProvider(providerId, baseUrl)
    activityText = "Saving API key..."
    clearErrorState()
    persistSettings({ providerId: providerId, authMode: authMode, baseUrl: baseUrl,
      endpointByProvider: JSON.stringify(endpointStore) })
    bridge.send({ op: "saveKey", baseUrl: baseUrl, key: key })
    apiKeyField.text = ""
  }

  function openKeyPage() {
    bridge.send({ op: "openKeyPage", providerId: providerId })
  }

  function startOAuth() {
    var baseUrl = endpointField.text.trim()
    endpointDraft = baseUrl
    var endpointStore = persistEndpointForProvider(providerId, baseUrl)
    activityText = "Opening " + currentProviderLabel() + " login..."
    clearErrorState()
    persistSettings({ providerId: providerId, authMode: "oauth", baseUrl: baseUrl,
      endpointByProvider: JSON.stringify(endpointStore) })
    bridge.send({ op: "startOAuth", providerId: providerId, baseUrl: baseUrl })
  }

  function activeMcpCount() {
    var count = 0
    for (var i = 0; i < mcpServers.length; i++)
      if (mcpServers[i].status === "connected") count++
    return count
  }

  function isMcpEnabled(key) {
    return enabledMcpKeys.indexOf(key) >= 0
  }

  function toggleMcp(key) {
    var next = enabledMcpKeys.slice()
    var index = next.indexOf(key)
    if (index >= 0) next.splice(index, 1)
    else next.push(key)
    enabledMcpKeys = next
    persistSettings({ mcpEnabled: JSON.stringify(enabledMcpKeys) })
  }

  function canShowChatTools() {
    return allMcpServers.length > 0 || enabledMcpKeys.length > 0
  }

  function toolsPending() {
    return connected && activeMcpEnabled !== JSON.stringify(enabledMcpKeys)
  }

  function toolsButtonText() {
    return enabledMcpKeys.length > 0 ? "Tools " + enabledMcpKeys.length : "Tools"
  }

  function toolsSummaryText() {
    return enabledMcpKeys.length + " selected / " + activeMcpCount() + " connected / "
      + allMcpServers.length + " found" + (toolsPending() ? " / reload to apply" : "")
  }

  function mcpStatus(key) {
    for (var i = 0; i < mcpServers.length; i++)
      if (mcpServers[i].key === key) return mcpServers[i].status
    return isMcpEnabled(key) ? "selected, reconnect to load" : "off"
  }

  function seedMcpSelectionFromConfiguredPath() {
    var path = mcpPathField.text.trim()
    if (enabledMcpKeys.length > 0 || path === "") return
    var next = []
    for (var i = 0; i < allMcpServers.length; i++)
      if (allMcpServers[i].path === path) next.push(allMcpServers[i].key)
    if (next.length === 0) return
    enabledMcpKeys = next
    persistSettings({ mcpEnabled: JSON.stringify(enabledMcpKeys) })
  }

  function attachmentKind(source) {
    var lower = String(source || "").toLowerCase()
    if (lower.match(/\.(png|jpe?g|webp|gif|bmp|heic|avif)(\?|$)/)) return "image"
    if (lower.match(/\.(mp4|mov|webm|mkv|avi|m4v)(\?|$)/)) return "video"
    if (lower.match(/\.(mp3|wav|m4a|flac|ogg)(\?|$)/)) return "audio"
    if (lower.match(/\.(pdf|txt|md|json|csv|log|yaml|yml)(\?|$)/)) return "file"
    return "file"
  }

  function attachmentLabel(source) {
    var text = String(source || "")
    if (text.indexOf("://") >= 0) return text
    var slash = Math.max(text.lastIndexOf("/"), text.lastIndexOf("\\"))
    return slash >= 0 && slash < text.length - 1 ? text.slice(slash + 1) : text
  }

  function attachmentFromSource(source) {
    return { source: source, label: attachmentLabel(source), kind: attachmentKind(source) }
  }

  function filePathFromUrl(url) {
    var text = String(url || "")
    if (text.indexOf("file://") === 0) text = decodeURIComponent(text.replace(/^file:\/\//, ""))
    return text
  }

  function addAttachmentSource(source) {
    source = String(source || "").trim()
    if (source === "") return
    attachments = attachments.concat([attachmentFromSource(source)])
  }

  function addAttachmentUrls(urls) {
    for (var i = 0; i < urls.length; i++) addAttachmentSource(filePathFromUrl(urls[i]))
  }

  function addAttachment() {
    var source = attachmentField.text.trim()
    if (source === "") {
      activityText = "Opening file picker..."
      bridge.send({ op: "pickFiles" })
      return
    }
    addAttachmentSource(source)
    attachmentField.text = ""
  }

  function removeAttachment(index) {
    var next = attachments.slice()
    next.splice(index, 1)
    attachments = next
  }

  function copyMessage(message) {
    var copy = {}
    for (var key in message) copy[key] = message[key]
    return copy
  }

  function roleColor(role, status) {
    if (role === "You") return root.userAccent
    if (role === "AI") return root.aiAccent
    if (role === "Tool") return status === "error" ? Color.urgent : root.toolAccent
    return Color.popups.text
  }

  function roleFill(role) {
    if (role === "You") return Style.normalFillFor(Color.popups.text, Color.accent)
    if (role === "AI") return Style.selectedFillFor(Color.popups.text, Color.accent)
    if (role === "Tool") return Style.normalFillFor(root.toolAccent, Color.accent)
    return Style.normalFillFor(Color.popups.text, Color.accent)
  }

  function roleBorder(role, status) {
    if (role === "You") return Style.normalBorderFor(Color.popups.text, Color.accent)
    if (role === "AI") return Style.selectedBorderFor(Color.popups.text, Color.accent)
    if (role === "Tool") return Style.normalBorderFor(status === "error" ? Color.urgent : root.toolAccent, Color.accent)
    return Style.normalBorderFor(Color.popups.text, Color.accent)
  }

  function messageTextColor(role, status) {
    if (role === "Tool") return status === "error" ? Color.urgent : root.toolAccent
    return Color.popups.text
  }

  function hasDebugDetails() {
    return errorDebug && typeof errorDebug === "object" && Object.keys(errorDebug).length > 0
  }

  function debugDetailsText() {
    if (!hasDebugDetails()) return ""
    try { return JSON.stringify(errorDebug, null, 2) } catch (e) { return String(errorDebug) }
  }

  function clearErrorState() {
    errorText = ""
    errorDebug = null
    debugOpen = false
    retryAvailable = false
    retryNotice = ""
  }

  function splitTableRow(line) {
    var text = String(line || "").trim()
    if (text.charAt(0) === "|") text = text.slice(1)
    if (text.charAt(text.length - 1) === "|") text = text.slice(0, -1)
    var cells = text.split("|")
    for (var i = 0; i < cells.length; i++) cells[i] = cells[i].trim()
    return cells
  }

  function isTableSeparator(line) {
    if (String(line || "").indexOf("|") < 0) return false
    var cells = splitTableRow(line)
    if (cells.length < 2) return false
    for (var i = 0; i < cells.length; i++) {
      if (!cells[i].match(/^:?-{3,}:?$/)) return false
    }
    return true
  }

  function looksLikeTableRow(line) {
    return String(line || "").indexOf("|") >= 0 && splitTableRow(line).length >= 2
  }

  function normalizedTableRow(cells, count) {
    var row = []
    for (var i = 0; i < count; i++) row.push(i < cells.length ? String(cells[i]) : "")
    return row
  }

  function messageText(message, modelIndex) {
    if (modelIndex === assistantDraftIndex && message && message.role === "AI")
      return assistantVisibleText + (assistantDraftIndex >= 0 ? " |" : "")
    return String((message && message.text) || "") + (message && message.streaming ? " |" : "")
  }

  function messageBlocks(message, modelIndex) {
    var role = String((message && message.role) || "")
    var text = messageText(message, modelIndex)
    if (role !== "AI") return text === "" ? [] : [{ kind: "text", text: text }]

    var lines = text.split("\n")
    var blocks = []
    var buffer = []
    var inFence = false
    var i = 0
    while (i < lines.length) {
      if (lines[i].match(/^\s*```/)) {
        inFence = !inFence
        buffer.push(lines[i])
        i += 1
        continue
      }
      if (!inFence && i + 1 < lines.length && looksLikeTableRow(lines[i]) && isTableSeparator(lines[i + 1])) {
        if (buffer.length > 0) {
          blocks.push({ kind: "text", text: buffer.join("\n") })
          buffer = []
        }
        var header = splitTableRow(lines[i])
        var columnCount = header.length
        var rows = []
        i += 2
        while (i < lines.length && looksLikeTableRow(lines[i])) {
          rows.push(normalizedTableRow(splitTableRow(lines[i]), columnCount))
          i += 1
        }
        blocks.push({ kind: "table", header: normalizedTableRow(header, columnCount), rows: rows, columnCount: columnCount })
        continue
      }
      buffer.push(lines[i])
      i += 1
    }
    if (buffer.length > 0) blocks.push({ kind: "text", text: buffer.join("\n") })
    return blocks
  }

  function tableDisplayRows(table) {
    var rows = [{ header: true, cells: table.header || [] }]
    for (var i = 0; i < (table.rows || []).length; i++) rows.push({ header: false, cells: table.rows[i] })
    return rows
  }

  function tableColumnWidth(table, column) {
    var maxChars = String((table.header || [])[column] || "").length
    var rows = table.rows || []
    for (var i = 0; i < rows.length; i++) maxChars = Math.max(maxChars, String((rows[i] || [])[column] || "").length)
    return Math.max(Style.space(82), Math.min(Style.space(260), Math.round(maxChars * Style.font.body * 0.58) + Style.space(22)))
  }

  function tableWidth(table) {
    var total = 0
    for (var i = 0; i < (table.columnCount || 0); i++) total += tableColumnWidth(table, i)
    return total
  }

  function toolSummary(message, expanded) {
    var text = String((message && message.text) || "")
    var name = text.split(" -> ")[0]
    var status = String((message && message.status) || "ok")
    return (status === "error" ? "Tool error" : "Tool call") + (name ? ": " + name : "") + (expanded ? " / click to collapse" : " / click to expand")
  }

  function updateAssistantDraft(text, streaming) {
    if (assistantDraftIndex < 0 || assistantDraftIndex >= messages.length) return
    if (streaming) return
    var next = messages.slice()
    var message = copyMessage(next[assistantDraftIndex])
    message.text = text
    message.streaming = streaming
    next[assistantDraftIndex] = message
    messages = next
    Qt.callLater(function() { transcript.positionViewAtEnd() })
  }

  function ensureAssistantDraft() {
    if (assistantDraftIndex >= 0 && assistantDraftIndex < messages.length && messages[assistantDraftIndex].role === "AI") return
    messages = messages.concat([{ role: "AI", text: "", streaming: true }])
    assistantDraftIndex = messages.length - 1
    assistantTargetText = ""
    assistantVisibleText = ""
    assistantDraftStreaming = true
  }

  function completeAssistantAnimation() {
    if (assistantDraftIndex >= 0 && assistantTargetText !== assistantVisibleText)
      updateAssistantDraft(assistantTargetText, false)
    assistantAnimation.stop()
    assistantDraftIndex = -1
    assistantTargetText = ""
    assistantVisibleText = ""
    assistantDraftStreaming = false
  }

  function discardAssistantDraft() {
    assistantAnimation.stop()
    if (assistantDraftIndex >= 0 && assistantDraftIndex < messages.length) {
      var next = messages.slice()
      next.splice(assistantDraftIndex, 1)
      messages = next
    }
    assistantDraftIndex = -1
    assistantTargetText = ""
    assistantVisibleText = ""
    assistantDraftStreaming = false
  }

  function queueAssistantText(text) {
    if (text === "") return
    ensureAssistantDraft()
    assistantTargetText += text
    assistantDraftStreaming = true
    if (!assistantAnimation.running) assistantAnimation.start()
  }

  function finishAssistantText(text, streamed) {
    ensureAssistantDraft()
    if (!streamed || assistantTargetText === "") {
      assistantTargetText = text
      assistantVisibleText = ""
    } else if (text.length > assistantTargetText.length) {
      assistantTargetText = text
    }
    assistantDraftStreaming = false
    if (!assistantAnimation.running) assistantAnimation.start()
  }

  function sendMessage() {
    var prompt = input.text.trim()
    if ((prompt === "" && attachments.length === 0) || sending || !ready || selectedModel === "") return
    completeAssistantAnimation()
    var outgoingAttachments = attachments.slice()
    input.text = ""
    attachments = []
    messages = messages.concat([{ role: "You", text: prompt, attachments: outgoingAttachments }])
    sending = true
    clearErrorState()
    Qt.callLater(function() { transcript.positionViewAtEnd() })
    bridge.send({ op: "chat", prompt: prompt, thinkingLevel: thinkingLevel, attachments: outgoingAttachments })
  }

  function retryLastMessage() {
    if (!retryAvailable || sending || !ready || selectedModel === "") return
    discardAssistantDraft()
    sending = true
    errorText = ""
    errorDebug = null
    debugOpen = false
    retryNotice = "Retrying..."
    Qt.callLater(function() { transcript.positionViewAtEnd() })
    bridge.send({ op: "retry", thinkingLevel: thinkingLevel })
  }

  function stopResponse() {
    if (!sending) return
    activityText = "Stopping..."
    bridge.send({ op: "stop" })
  }

  function clearChat() {
    completeAssistantAnimation()
    messages = []
    attachments = []
    currentChatId = ""
    clearErrorState()
    bridge.send({ op: "reset" })
  }

  function loadChat(id) {
    if (sending) stopResponse()
    completeAssistantAnimation()
    bridge.send({ op: "loadChat", id: id })
    settingsOpen = false
    chatSidebarOpen = false
    renamingChatId = ""
    renameDraft = ""
  }

  function deleteChat(id) {
    if (renamingChatId === id) {
      renamingChatId = ""
      renameDraft = ""
    }
    bridge.send({ op: "deleteChat", id: id })
  }

  function startRenameChat(id, title) {
    renamingChatId = String(id)
    renameDraft = String(title || "")
  }

  function cancelRenameChat() {
    renamingChatId = ""
    renameDraft = ""
  }

  function renameChat(id, title) {
    var clean = String(title || "").trim()
    if (clean === "") return
    renamingChatId = ""
    renameDraft = ""
    bridge.send({ op: "renameChat", id: id, title: clean })
  }

  function openSettings() {
    settingsOpen = true
    bridge.send({ op: "discover" })
    bridge.send({ op: "listChats" })
  }

  function closeSettings() {
    settingsOpen = false
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function open() {
    var wasOpen = opened
    drawerCloseTimer.stop()
    controller.show()
    settingsOpen = false
    if (!wasOpen) {
      drawerOpen = false
      Qt.callLater(function() { if (root.opened) root.drawerOpen = true })
    } else {
      drawerOpen = true
    }
    var startupEndpoint = configuredBaseUrl || effectiveEndpointForProvider(providerId)
    if (startupEndpoint !== "") {
      endpointDraft = startupEndpoint
      endpointField.text = startupEndpoint
      mcpPathField.text = configuredMcpPath
      if (configuredBaseUrl !== "") connect()
    } else if (providers.length > 0) {
      var provider = currentProvider()
      if (provider.baseUrl) {
        endpointDraft = provider.baseUrl
        endpointField.text = provider.baseUrl
      }
    }
  }

  function close() {
    if (!opened) return
    drawerOpen = false
    drawerCloseTimer.restart()
  }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  BridgeController {
    id: bridge
    executable: root.bridgePath
    onReady: {
      bridge.send({ op: "discover" })
      bridge.send({ op: "listChats" })
      if (root.configuredBaseUrl !== "")
        Qt.callLater(function() { root.connect() })
    }
    onFailed: function(message) {
      root.connected = false
      root.activeProviderId = ""
      root.activeAuthMode = ""
      root.activeBaseUrl = ""
      root.activeMcpEnabled = ""
      root.sending = false
      root.errorDebug = null
      root.debugOpen = false
      root.retryAvailable = false
      root.retryNotice = ""
      root.errorText = message
    }
    onLine: function(value) {
      var event = null
      try { event = JSON.parse(value) } catch (e) { return }
      if (event.type === "discovery") {
        root.providers = event.providers || []
        root.mcpConfigs = event.mcpConfigs || []
        root.allMcpServers = event.mcpServers || []
        root.normalizeAuthMode()
        root.seedMcpSelectionFromConfiguredPath()
        if (endpointField.text.trim() === "") {
          var provider = root.currentProvider()
          if (provider.baseUrl) {
            root.endpointDraft = provider.baseUrl
            endpointField.text = provider.baseUrl
          }
        }
      } else if (event.type === "connected") {
        root.connected = true
        root.activeProviderId = event.providerId || root.providerId
        root.activeAuthMode = event.authMode || root.authMode
        root.activeBaseUrl = event.baseUrl || endpointField.text.trim()
        root.activeMcpEnabled = JSON.stringify(root.enabledMcpKeys)
        root.endpointDraft = root.activeBaseUrl
        endpointField.text = root.activeBaseUrl
        root.activityText = ""
        root.models = event.models || []
        root.mcpServers = event.mcp || []
        root.selectedModel = event.model || root.selectedModel
        if (!root.models.some(function(model) { return model.id === root.selectedModel }))
          root.selectedModel = root.models.length > 0 ? root.models[0].id : ""
        root.normalizeThinkingLevel()
        var modelStore = root.modelStoreWith(root.selectedModel)
        var endpointStore = root.endpointStoreWith(root.providerId, root.activeBaseUrl)
        root.modelByProvider = modelStore
        root.endpointByProvider = endpointStore
        root.persistSettings({ providerId: root.providerId, authMode: root.authMode,
          baseUrl: endpointField.text.trim(), endpointByProvider: JSON.stringify(endpointStore),
          model: root.selectedModel,
          modelByProvider: JSON.stringify(modelStore), thinkingLevel: root.thinkingLevel,
          mcpPath: mcpPathField.text.trim(), mcpEnabled: JSON.stringify(root.enabledMcpKeys) })
        root.clearErrorState()
      } else if (event.type === "chat") {
        root.sending = false
        root.activityText = ""
        root.clearErrorState()
        root.currentChatId = event.chatId || root.currentChatId
        root.finishAssistantText(event.text || "The model finished without text.", Boolean(event.streamed))
      } else if (event.type === "chatDelta") {
        root.currentChatId = event.chatId || root.currentChatId
        root.retryNotice = ""
        root.queueAssistantText(event.text || "")
      } else if (event.type === "chatRetry") {
        var attempt = Number(event.attempt || 0)
        var maxAttempts = Number(event.maxAttempts || 0)
        var delay = Number(event.delay || 0)
        root.activityText = ""
        root.retryNotice = "Retrying in " + delay.toFixed(delay >= 10 ? 0 : 1) + "s"
          + (attempt > 0 && maxAttempts > 0 ? " (attempt " + attempt + " of " + maxAttempts + ")" : "")
        root.errorDebug = event.debug || null
        root.debugOpen = false
      } else if (event.type === "chatStopped") {
        root.sending = false
        root.activityText = ""
        root.retryNotice = ""
        root.discardAssistantDraft()
        root.errorText = "Stopped."
        root.errorDebug = null
        root.debugOpen = false
        root.retryAvailable = root.ready && root.messages.length > 0
      } else if (event.type === "toolCall") {
        root.messages = root.messages.concat([{ role: "Tool", text: event.text || event.name, status: event.status || "ok" }])
        Qt.callLater(function() { transcript.positionViewAtEnd() })
      } else if (event.type === "chats") {
        root.chats = event.chats || []
        root.currentChatId = event.currentChatId || root.currentChatId
      } else if (event.type === "chatLoaded") {
        root.completeAssistantAnimation()
        root.currentChatId = event.chatId || ""
        root.messages = event.messages || []
        root.clearErrorState()
        Qt.callLater(function() { transcript.positionViewAtEnd() })
      } else if (event.type === "chatReset") {
        root.completeAssistantAnimation()
        root.currentChatId = ""
        root.messages = []
        root.attachments = []
        root.clearErrorState()
      } else if (event.type === "keySaved") {
        root.activityText = ""
        root.errorDebug = null
        root.debugOpen = false
        root.retryAvailable = false
        root.retryNotice = ""
        root.errorText = "API key saved in the system keyring."
        bridge.send({ op: "discover" })
      } else if (event.type === "oauthStarted") {
        root.activityText = "Waiting for OAuth callback..."
        root.errorDebug = null
        root.debugOpen = false
        root.retryAvailable = false
        root.retryNotice = ""
        root.errorText = event.message || ("OAuth opened in the browser. Waiting for callback on " + event.redirectUri + ".")
      } else if (event.type === "oauthSaved") {
        root.errorDebug = null
        root.debugOpen = false
        root.retryAvailable = false
        root.retryNotice = ""
        root.errorText = root.providerOAuthKind(root.currentProvider()) === "openrouter" ? "API key saved. Connecting..." : "Login saved. Connecting..."
        bridge.send({ op: "discover" })
        root.connect()
      } else if (event.type === "notice") {
        root.activityText = ""
        root.errorDebug = null
        root.debugOpen = false
        root.retryAvailable = false
        root.retryNotice = ""
        root.errorText = event.message || ""
      } else if (event.type === "filesPicked") {
        root.activityText = ""
        root.addAttachmentUrls(event.files || [])
      } else if (event.type === "error") {
        root.sending = false
        if (event.op === "chat" || event.op === "retry") root.discardAssistantDraft()
        else root.completeAssistantAnimation()
        if (event.op !== "chat" && event.op !== "retry" && event.op !== "pickFiles" && event.op !== "renameChat" && event.op !== "deleteChat" && event.op !== "reset") {
          root.connected = false
          root.activeProviderId = ""
          root.activeAuthMode = ""
          root.activeBaseUrl = ""
          root.activeMcpEnabled = ""
        }
        root.activityText = ""
        root.retryNotice = ""
        root.errorDebug = event.debug || null
        root.debugOpen = false
        root.retryAvailable = (event.op === "chat" || event.op === "retry") && root.ready && root.messages.length > 0
        root.errorText = event.message || "The AI bridge failed."
      }
    }
    Component.onCompleted: bridge.start()
  }

  Timer {
    id: drawerCloseTimer
    interval: 170
    onTriggered: root.controller.hide()
  }

  Timer {
    id: assistantAnimation
    interval: 14
    repeat: true
    onTriggered: {
      var remaining = root.assistantTargetText.length - root.assistantVisibleText.length
      if (remaining <= 0) {
        if (!root.assistantDraftStreaming) {
          root.updateAssistantDraft(root.assistantVisibleText, false)
          root.assistantDraftIndex = -1
          root.assistantTargetText = ""
          root.assistantVisibleText = ""
          stop()
        }
        return
      }
      var step = remaining > 160 ? 8 : (remaining > 60 ? 4 : 2)
      root.assistantVisibleText += root.assistantTargetText.slice(root.assistantVisibleText.length,
        root.assistantVisibleText.length + step)
      root.updateAssistantDraft(root.assistantVisibleText, root.assistantDraftStreaming || root.assistantVisibleText.length < root.assistantTargetText.length)
      Qt.callLater(function() { transcript.positionViewAtEnd() })
    }
  }

  FloatingWindow {
    id: panel
    title: "Omarchy AI Chat"
    visible: root.opened || root.drawerOpen
    color: Color.popups.background
    implicitWidth: Style.space(900)
    implicitHeight: Style.space(740)
    minimumSize: Qt.size(Style.space(620), Style.space(500))

    onVisibleChanged: {
      if (!visible && root.opened) {
        root.drawerOpen = false
        root.controller.hide()
      }
      if (visible) {
        Qt.callLater(function() { (root.settingsOpen ? providerPicker : input).forceActiveFocus() })
      }
    }

    FocusScope {
      id: drawerContent
      x: Style.space(18)
      y: Style.space(18) + (root.drawerOpen ? 0 : Math.min(Style.space(96), panel.height * 0.18))
      width: panel.width - Style.space(36)
      height: panel.height - Style.space(36)
      opacity: root.drawerOpen ? 1.0 : 0.0
      focus: true

      Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

      Row {
        id: headerRow
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: Math.max(Style.space(180), parent.width - statusLabel.implicitWidth
            - setupButton.implicitWidth - (chatsButton.visible ? chatsButton.implicitWidth : 0)
            - (newChatButton.visible ? newChatButton.implicitWidth : 0)
            - Style.space(32))
          text: root.settingsOpen ? "Setup AI Chat" : "AI Chat"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          id: statusLabel
          anchors.verticalCenter: parent.verticalCenter
          text: root.statusText()
          color: root.ready || root.activityText !== "" ? Color.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Button {
          id: setupButton
          text: root.settingsOpen ? "Back" : "Setup"
          bordered: true
          selected: root.settingsOpen
          onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
        }
        Button {
          id: chatsButton
          text: root.chatSidebarOpen ? "Hide chats" : "Chats"
          bordered: true
          selected: root.chatSidebarOpen
          visible: !root.settingsOpen
          onClicked: {
            root.chatSidebarOpen = !root.chatSidebarOpen
            if (root.chatSidebarOpen) bridge.send({ op: "listChats" })
          }
        }
        Button {
          id: newChatButton
          text: "New chat"
          bordered: true
          visible: !root.settingsOpen
          enabled: !root.sending
          onClicked: root.clearChat()
        }
      }

      Flickable {
        width: parent.width
        height: parent.height - headerRow.height - Style.space(10)
        visible: root.settingsOpen
        contentWidth: width
        contentHeight: setupContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: setupContent
          width: parent.width
          spacing: Style.space(12)

          Rectangle {
            width: parent.width
            height: statusContent.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: root.ready ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

            Column {
              id: statusContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - statusPill.width - parent.spacing
                  text: root.ready ? "Ready to chat" : (root.connected ? "Changes pending" : "Setup")
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Rectangle {
                  id: statusPill
                  width: statusPillText.implicitWidth + Style.space(18)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: root.ready ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
                  Text {
                    id: statusPillText
                    anchors.centerIn: parent
                    text: root.ready ? "ready" : (root.connected ? "pending" : (root.activityText !== "" ? "working" : "not connected"))
                    color: root.ready ? Color.accent : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: root.ready
                  }
                }
              }
              Text {
                width: parent.width
                text: root.activeConnectionText()
                textFormat: Text.PlainText
                color: root.ready ? Color.accent : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: root.ready
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: root.activeConnectionDetail()
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Row {
                width: parent.width
                spacing: Style.space(8)
                Button {
                  text: "Go to chat"
                  selected: true
                  visible: root.ready
                  onClicked: root.closeSettings()
                }
                Button {
                  text: "Advanced"
                  bordered: true
                  selected: root.advancedOpen
                  onClicked: root.advancedOpen = !root.advancedOpen
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: accountContent.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

            Column {
              id: accountContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "1. Account"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Dropdown {
                id: providerPicker
                width: parent.width
                label: "Provider"
                value: root.providerId
                options: root.providerOptions
                onChanged: function(value) { root.selectProvider(value) }
              }
              Text {
                width: parent.width
                text: root.providerRowDescription(root.currentProvider())
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: "How to connect"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Flow {
                id: authModeFlow
                width: parent.width
                spacing: Style.space(8)
                Repeater {
                  model: root.authModeOptions
                  delegate: Button {
                    readonly property int columns: Math.max(1, Math.min(3, root.authModeOptions.length))
                    width: Math.max(Style.space(180), (authModeFlow.width - authModeFlow.spacing * (columns - 1)) / columns)
                    text: modelData.label
                    tooltipText: root.authModeDescription(modelData.value)
                    selected: root.authMode === modelData.value
                    bordered: root.authMode !== modelData.value
                    leftAlign: true
                    onClicked: root.selectAuthMode(modelData.value)
                  }
                }
              }
              Text {
                width: parent.width
                text: root.methodStatusText()
                textFormat: Text.PlainText
                color: root.methodStatusText().indexOf("connected") >= 0 || root.methodStatusText().indexOf("saved") >= 0 || root.authMode === "none" ? Color.accent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: root.methodStatusText().indexOf("connected") >= 0 || root.methodStatusText().indexOf("saved") >= 0
              }
              Text {
                width: parent.width
                text: root.connectionHelpText()
                textFormat: Text.PlainText
                color: root.ready ? Color.accent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Button {
                width: parent.width
                text: root.mainActionText()
                selected: true
                visible: root.authMode !== "key"
                enabled: root.authMode === "oauth" ? root.hasProviderOAuth() : endpointDraft.trim() !== ""
                onClicked: root.runMainAction()
              }
              Row {
                width: parent.width
                spacing: Style.space(8)
                visible: root.authMode === "key"
                TextField {
                  id: apiKeyField
                  width: parent.width - saveKeyButton.width - (keyPageButton.visible ? keyPageButton.width + parent.spacing : 0) - parent.spacing
                  password: true
                  placeholderText: "Paste API key"
                  onAccepted: root.saveApiKey()
                }
                Button {
                  id: saveKeyButton
                  text: "Save key"
                  selected: true
                  enabled: endpointField.text.trim() !== "" && apiKeyField.text !== ""
                  onClicked: root.saveApiKey()
                }
                Button {
                  id: keyPageButton
                  text: "API keys"
                  bordered: true
                  visible: root.currentProvider().keyUrl !== ""
                  onClicked: root.openKeyPage()
                }
              }
              Button {
                width: parent.width
                text: root.mainActionText()
                bordered: true
                visible: root.authMode === "key" && root.methodStatusText() === "API key saved"
                enabled: endpointDraft.trim() !== "" && root.methodStatusText() === "API key saved"
                onClicked: root.connect()
              }
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.advancedOpen || root.authMode !== "oauth"
                Text {
                  width: parent.width
                  text: "Endpoint (saved per provider)"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  id: endpointField
                  width: parent.width
                  placeholderText: "http://127.0.0.1:11434/v1"
                  text: root.configuredBaseUrl
                  onTextChanged: root.endpointDraft = text
                  onEditingFinished: {
                    root.endpointDraft = text.trim()
                    var endpointStore = root.persistEndpointForProvider(root.providerId, root.endpointDraft)
                    root.persistSettings({ baseUrl: root.endpointDraft, endpointByProvider: JSON.stringify(endpointStore) })
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: visible ? mcpContent.implicitHeight + Style.space(20) : 0
            visible: root.allMcpServers.length > 0 || root.enabledMcpKeys.length > 0 || root.advancedOpen
            radius: Style.cornerRadius
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

            Column {
              id: mcpContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - toolsScanButton.width - parent.spacing
                  text: "2. Tools"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Button {
                  id: toolsScanButton
                  text: "Rescan"
                  bordered: true
                  onClicked: bridge.send({ op: "discover" })
                }
              }
              Text {
                width: parent.width
                text: "Optional MCP tools. Select before loading models, or reload models after changing them."
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: root.enabledMcpKeys.length + " selected / " + root.activeMcpCount() + " connected / " + root.allMcpServers.length + " found"
                textFormat: Text.PlainText
                color: root.activeMcpCount() > 0 ? Color.accent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              TextField {
                id: mcpPathField
                width: parent.width
                visible: root.advancedOpen
                placeholderText: "Extra MCP JSON path"
                text: root.configuredMcpPath
              }
              Text {
                width: parent.width
                visible: root.allMcpServers.length === 0
                text: "No tools found. Rescan checks OpenCode, Claude, Cursor, VS Code, Windsurf, Zed and ~/.config/mcp."
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.allMcpServers
                delegate: Toggle {
                  width: parent.width
                  label: modelData.name
                  description: modelData.source + " / " + root.mcpStatus(modelData.key)
                  checked: root.isMcpEnabled(modelData.key)
                  onClicked: root.toggleMcp(modelData.key)
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: modelContent.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

            Column {
              id: modelContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "3. Model"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                width: parent.width
                visible: !root.ready
                text: root.connected ? "Load models again to apply the current setup." : "Load models after choosing an account and optional tools."
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              AdaptiveSearchableDropdown {
                id: setupModelPicker
                width: parent.width
                visible: root.ready
                label: "Active model"
                value: root.selectedModel
                options: root.modelOptions
                placeholderText: "Filter models..."
                emptyText: "No matching models"
                enabled: !root.sending
                onChanged: function(value) {
                  root.setSelectedModel(value, true)
                }
              }
              Text {
                width: parent.width
                visible: root.ready
                text: "Supports: " + root.modelCapabilitiesText()
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

        }
      }

      Row {
        id: chatShell
        width: parent.width
        height: parent.height - headerRow.height - Style.space(10)
        visible: !root.settingsOpen
        spacing: Style.space(10)

        Rectangle {
          id: chatSidebar
          width: root.chatSidebarOpen ? Math.min(Style.space(280), chatShell.width * 0.34) : 0
          height: parent.height
          visible: root.chatSidebarOpen
          radius: Style.cornerRadius
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
          clip: true

          Column {
            id: sidebarContent
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Row {
              id: sidebarHeader
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: parent.width - closeSidebarButton.width - parent.spacing
                text: "Saved chats"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Button {
                id: closeSidebarButton
                width: Style.space(32)
                text: ""
                iconText: "X"
                iconSize: Style.font.body
                tooltipText: "Close chats"
                bordered: true
                onClicked: root.chatSidebarOpen = false
              }
            }

            Flickable {
              width: parent.width
              height: parent.height - sidebarHeader.height - Style.space(8)
              contentWidth: width
              contentHeight: sidebarChats.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: sidebarChats
                width: parent.width
                spacing: Style.space(8)

                Text {
                  width: parent.width
                  visible: root.chats.length === 0
                  text: "Chats are saved after the first assistant response."
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Repeater {
                  model: root.chats
                  delegate: Column {
                    width: parent.width
                    spacing: Style.space(6)

                    Text {
                      width: parent.width
                      visible: Boolean(modelData.showGroup)
                      text: modelData.group || "Older"
                      textFormat: Text.PlainText
                      color: Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Rectangle {
                      width: parent.width
                      height: chatRow.implicitHeight + Style.space(12)
                      radius: Style.cornerRadius
                      color: modelData.id === root.currentChatId
                        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                        : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

                      Column {
                        id: chatRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(6)
                        spacing: Style.space(5)

                        Text {
                          width: parent.width
                          visible: root.renamingChatId !== modelData.id
                          text: modelData.title
                          textFormat: Text.PlainText
                          color: modelData.id === root.currentChatId ? Color.accent : Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          elide: Text.ElideRight
                        }
                        Row {
                          width: parent.width
                          visible: root.renamingChatId === modelData.id
                          spacing: Style.space(5)
                          TextField {
                            width: parent.width - renameSaveButton.width - renameCancelButton.width - parent.spacing * 2
                            text: root.renameDraft
                            onTextChanged: if (visible) root.renameDraft = text
                            onAccepted: root.renameChat(modelData.id, text)
                          }
                          Button {
                            id: renameSaveButton
                            width: Style.space(30)
                            text: ""
                            iconText: "✓"
                            iconSize: Style.font.body
                            tooltipText: "Save title"
                            selected: true
                            enabled: root.renameDraft.trim() !== ""
                            horizontalPadding: Style.space(5)
                            onClicked: root.renameChat(modelData.id, root.renameDraft)
                          }
                          Button {
                            id: renameCancelButton
                            width: Style.space(30)
                            text: ""
                            iconText: "X"
                            iconSize: Style.font.body
                            tooltipText: "Cancel"
                            bordered: true
                            horizontalPadding: Style.space(5)
                            onClicked: root.cancelRenameChat()
                          }
                        }
                        Text {
                          width: parent.width
                          text: modelData.model || modelData.providerId || "unknown model"
                          textFormat: Text.PlainText
                          color: Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                        Row {
                          width: parent.width
                          visible: root.renamingChatId !== modelData.id
                          spacing: Style.space(6)
                          Button {
                            width: parent.width - renameChatButton.width - deleteChatButton.width - parent.spacing * 2
                            text: "Load"
                            bordered: true
                            leftAlign: true
                            onClicked: root.loadChat(modelData.id)
                          }
                          Button {
                            id: renameChatButton
                            width: Style.space(30)
                            text: ""
                            iconText: "✎"
                            iconSize: Style.font.body
                            tooltipText: "Rename"
                            bordered: true
                            horizontalPadding: Style.space(5)
                            onClicked: root.startRenameChat(modelData.id, modelData.title)
                          }
                          Button {
                            id: deleteChatButton
                            width: Style.space(30)
                            text: ""
                            iconText: "X"
                            iconSize: Style.font.body
                            tooltipText: "Delete"
                            foreground: Color.urgent
                            accent: Color.urgent
                            bordered: true
                            horizontalPadding: Style.space(5)
                            onClicked: root.deleteChat(modelData.id)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Column {
          id: chatColumn
          width: parent.width - (chatSidebar.visible ? chatSidebar.width + parent.spacing : 0)
          height: parent.height
          spacing: Style.space(8)

          Row {
            id: chatControlRow
            width: parent.width
            visible: root.ready
            spacing: Style.space(8)
            AdaptiveSearchableDropdown {
              id: modelPicker
              width: Math.max(Style.space(170), parent.width
                - (thinkingPicker.visible ? thinkingPicker.width + parent.spacing : 0)
                - (toolsToggleButton.visible ? toolsToggleButton.width + parent.spacing : 0))
              label: "Model"
              showLabel: false
              value: root.selectedModel
              options: root.modelOptions
              placeholderText: "Filter models..."
              emptyText: "No matching models"
              enabled: root.ready && !root.sending
              onChanged: function(value) { root.setSelectedModel(value, true) }
            }
            Dropdown {
              id: thinkingPicker
              width: Style.space(170)
              visible: root.thinkingModeOptions.length > 0
              label: "Thinking"
              showLabel: false
              value: root.thinkingLevel
              options: root.thinkingModeOptions
              enabled: root.ready && !root.sending
              onChanged: function(value) { root.setThinkingLevel(value) }
            }
            Button {
              id: toolsToggleButton
              text: root.toolsButtonText()
              bordered: !root.chatToolsOpen
              selected: root.chatToolsOpen
              visible: root.canShowChatTools()
              enabled: !root.sending
              tooltipText: root.toolsSummaryText()
              onClicked: {
                root.chatToolsOpen = !root.chatToolsOpen
                if (root.chatToolsOpen) bridge.send({ op: "discover" })
              }
            }
          }

          Rectangle {
            id: chatToolsPanel
            width: parent.width
            height: visible ? chatToolsContent.implicitHeight + Style.space(14) : 0
            visible: root.chatToolsOpen && root.canShowChatTools()
            radius: Style.cornerRadius
            color: Style.selectedFillFor(Color.popups.text, Color.accent)
            border.color: Style.normalBorderFor(Color.popups.text, Color.accent)
            border.width: 1
            clip: true

            Column {
              id: chatToolsContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(7)
              spacing: Style.space(7)

              Row {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  width: Math.max(Style.space(120), parent.width - toolsRescanButton.width
                    - (toolsApplyButton.visible ? toolsApplyButton.width + parent.spacing : 0)
                    - parent.spacing)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.toolsSummaryText()
                  textFormat: Text.PlainText
                  color: root.toolsPending() ? Color.accent : Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: root.toolsPending()
                  elide: Text.ElideRight
                }
                Button {
                  id: toolsRescanButton
                  text: "Rescan"
                  bordered: true
                  onClicked: bridge.send({ op: "discover" })
                }
                Button {
                  id: toolsApplyButton
                  text: "Apply"
                  selected: true
                  visible: root.toolsPending()
                  enabled: !root.sending
                  tooltipText: "Reload models with selected tools"
                  onClicked: root.connect()
                }
              }

              Text {
                width: parent.width
                visible: root.allMcpServers.length === 0
                text: "No tools found yet. Rescan checks known MCP config locations."
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: root.allMcpServers
                delegate: Toggle {
                  width: chatToolsContent.width
                  label: String(modelData.name || modelData.key || "Tool")
                  description: String(modelData.source || "MCP") + " / " + root.mcpStatus(String(modelData.key || ""))
                  checked: root.isMcpEnabled(String(modelData.key || ""))
                  foreground: Color.popups.text
                  onClicked: root.toggleMcp(String(modelData.key || ""))
                }
              }
            }
          }

          Flow {
            id: capabilityFlow
            width: parent.width
            height: visible ? implicitHeight : 0
            visible: root.ready
            spacing: Style.space(6)
            Repeater {
              model: root.chatCapabilityChips()
              delegate: Rectangle {
                width: chipText.implicitWidth + Style.space(16)
                height: Style.space(24)
                radius: Style.cornerRadius
                color: Util.alpha(Color.accent, 0.14)
                border.color: Util.alpha(Color.accent, 0.28)
                border.width: 1
                Text {
                  id: chipText
                  anchors.centerIn: parent
                  text: modelData
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          Column {
            id: noticeArea
            width: parent.width
            visible: root.errorText !== "" || root.retryNotice !== "" || !root.ready
            spacing: Style.space(6)

            Text {
              id: messageLine
              width: parent.width
              text: root.retryNotice !== "" ? root.retryNotice
                : (root.errorText !== "" ? root.errorText : "Open Setup and load models before chatting.")
              textFormat: Text.PlainText
              color: root.retryNotice !== "" || root.errorText.indexOf("saved") !== -1 || root.errorText.indexOf("Opened") !== -1
                ? Color.accent : (root.errorText !== "" ? Color.urgent : Color.muted)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              visible: root.errorText !== "" && (root.retryAvailable || root.hasDebugDetails())
              spacing: Style.space(8)

              Button {
                text: "Retry"
                selected: true
                visible: root.retryAvailable
                enabled: root.ready && !root.sending
                onClicked: root.retryLastMessage()
              }

              Button {
                text: root.debugOpen ? "Hide debug" : "Show debug"
                bordered: true
                visible: root.hasDebugDetails()
                onClicked: root.debugOpen = !root.debugOpen
              }
            }

            Rectangle {
              id: debugPanel
              width: parent.width
              height: visible ? Math.min(Style.space(190), debugText.implicitHeight + Style.space(14)) : 0
              visible: root.debugOpen && root.hasDebugDetails()
              radius: Style.cornerRadius
              color: Style.normalFillFor(Color.popups.text, Color.accent)
              border.color: Style.normalBorderFor(Color.popups.text, Color.accent)
              border.width: 1
              clip: true

              Flickable {
                anchors.fill: parent
                anchors.margins: Style.space(7)
                contentWidth: width
                contentHeight: debugText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar { policy: debugText.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

                Text {
                  id: debugText
                  width: parent.width
                  text: root.debugDetailsText()
                  textFormat: Text.PlainText
                  color: Color.muted
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                }
              }
            }
          }

          Rectangle {
            id: chatPane
            width: parent.width
            height: Math.max(Style.space(260), parent.height
              - (chatControlRow.visible ? chatControlRow.height + parent.spacing : 0)
              - (chatToolsPanel.visible ? chatToolsPanel.height + parent.spacing : 0)
              - (capabilityFlow.visible ? capabilityFlow.height + parent.spacing : 0)
              - (noticeArea.visible ? noticeArea.height + parent.spacing : 0)
              - composer.height - Style.space(16))
            color: Style.normalFillFor(Color.popups.text, Color.accent)
            radius: Style.cornerRadius
            clip: true

            ListView {
              id: transcript
              anchors.fill: parent
              anchors.margins: Style.space(10)
              model: root.messages
              spacing: Style.space(12)
              clip: true
              delegate: Rectangle {
                id: messageCard
                property var messageData: modelData
                property string messageRole: String(modelData.role || "")
                property bool isTool: messageRole === "Tool"
                property bool toolExpanded: false
                property int messageIndex: index
                width: transcript.width
                height: messageContent.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: root.roleFill(messageRole)
                border.color: root.roleBorder(messageRole, String(modelData.status || ""))
                border.width: 1

                Column {
                  id: messageContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(7)
                  spacing: Style.space(5)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      id: roleName
                      text: messageCard.messageRole
                      color: root.roleColor(messageCard.messageRole, String(messageCard.messageData.status || ""))
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Text {
                      width: Math.max(0, parent.width - roleName.implicitWidth - parent.spacing)
                      visible: messageCard.isTool
                      text: root.toolSummary(messageCard.messageData, messageCard.toolExpanded)
                      textFormat: Text.PlainText
                      color: root.messageTextColor("Tool", String(messageCard.messageData.status || ""))
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Repeater {
                    model: messageCard.messageData.attachments || []
                    delegate: Rectangle {
                      width: Math.min(messageContent.width, attachmentText.implicitWidth + Style.space(14))
                      height: Style.space(23)
                      radius: Style.cornerRadius
                      color: Style.normalFillFor(Color.popups.text, Color.accent)
                      border.color: Style.normalBorderFor(Color.popups.text, Color.accent)
                      border.width: 1
                      Text {
                        id: attachmentText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(7)
                        anchors.rightMargin: Style.space(7)
                        text: "[" + String(modelData.kind || "file") + "] " + String(modelData.label || "attachment")
                        textFormat: Text.PlainText
                        color: root.userAccent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                      }
                    }
                  }

                  Column {
                    width: parent.width
                    spacing: Style.space(7)
                    visible: !messageCard.isTool || messageCard.toolExpanded

                    Text {
                      width: parent.width
                      visible: messageCard.messageIndex === root.assistantDraftIndex
                      text: root.assistantVisibleText + " |"
                      textFormat: Text.PlainText
                      color: root.messageTextColor(messageCard.messageRole, String(messageCard.messageData.status || ""))
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      wrapMode: Text.Wrap
                    }

                    Repeater {
                      model: messageCard.messageIndex === root.assistantDraftIndex ? [] : root.messageBlocks(messageCard.messageData, messageCard.messageIndex)
                      delegate: Column {
                        id: blockDelegate
                        property var block: modelData
                        width: parent.width
                        spacing: Style.space(5)

                        Text {
                          width: parent.width
                          visible: blockDelegate.block.kind === "text" && blockDelegate.block.text !== ""
                          text: blockDelegate.block.text
                          textFormat: messageCard.messageRole === "AI" ? Text.MarkdownText : Text.PlainText
                          color: root.messageTextColor(messageCard.messageRole, String(messageCard.messageData.status || ""))
                          linkColor: root.roleColor(messageCard.messageRole, String(messageCard.messageData.status || ""))
                          font.family: Style.font.family
                          font.pixelSize: messageCard.isTool ? Style.font.caption : Style.font.body
                          wrapMode: Text.Wrap
                        }

                        Flickable {
                          id: tableScroll
                          width: parent.width
                          height: visible ? tableGrid.implicitHeight : 0
                          visible: blockDelegate.block.kind === "table"
                          contentWidth: Math.max(width, tableGrid.width)
                          contentHeight: tableGrid.implicitHeight
                          clip: true
                          boundsBehavior: Flickable.StopAtBounds
                          flickableDirection: Flickable.HorizontalFlick
                          interactive: contentWidth > width
                          ScrollBar.horizontal: ScrollBar { policy: tableScroll.contentWidth > tableScroll.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

                          Column {
                            id: tableGrid
                            width: root.tableWidth(blockDelegate.block)
                            spacing: 0
                            Repeater {
                              model: root.tableDisplayRows(blockDelegate.block)
                              delegate: Row {
                                id: tableRow
                                property var rowData: modelData
                                spacing: 0
                                Repeater {
                                  model: tableRow.rowData.cells || []
                                  delegate: Rectangle {
                                    width: root.tableColumnWidth(blockDelegate.block, index)
                                    height: Math.max(Style.space(30), cellText.implicitHeight + Style.space(12))
                                    color: tableRow.rowData.header ? Style.selectedFillFor(Color.popups.text, Color.accent) : Style.normalFillFor(Color.popups.text, Color.accent)
                                    border.color: tableRow.rowData.header ? Style.selectedBorderFor(Color.popups.text, Color.accent) : Style.normalBorderFor(Color.popups.text, Color.accent)
                                    border.width: 1
                                    Text {
                                      id: cellText
                                      anchors.left: parent.left
                                      anchors.right: parent.right
                                      anchors.verticalCenter: parent.verticalCenter
                                      anchors.leftMargin: Style.space(7)
                                      anchors.rightMargin: Style.space(7)
                                      text: String(modelData || "")
                                      textFormat: Text.PlainText
                                      color: tableRow.rowData.header ? root.aiAccent : Color.popups.text
                                      font.family: Style.font.family
                                      font.pixelSize: Style.font.caption
                                      font.bold: tableRow.rowData.header
                                      wrapMode: Text.Wrap
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: messageCard.isTool
                  cursorShape: Qt.PointingHandCursor
                  onClicked: messageCard.toolExpanded = !messageCard.toolExpanded
                }
              }
              footer: Item {
                width: transcript.width
                height: thinkingCard.visible ? thinkingCard.height + Style.space(8) : 0
                visible: height > 0

                Rectangle {
                  id: thinkingCard
                  width: parent.width
                  height: Style.space(58)
                  visible: root.sending && root.assistantDraftIndex < 0
                  radius: Style.cornerRadius
                  color: Style.selectedFillFor(Color.popups.text, Color.accent)
                  border.color: Style.normalBorderFor(Color.popups.text, Color.accent)
                  border.width: 1

                  SequentialAnimation on opacity {
                    running: thinkingCard.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.78; duration: 720; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 720; easing.type: Easing.InOutSine }
                  }

                  Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(10)

                    Rectangle {
                      id: logoBadge
                      width: Style.space(104)
                      height: Style.space(34)
                      anchors.verticalCenter: parent.verticalCenter
                      radius: Math.round(height / 2)
                      color: root.aiAccent
                      border.color: Style.normalBorderFor(Color.popups.text, Color.accent)
                      border.width: 1
                      clip: true

                      SequentialAnimation on scale {
                        running: thinkingCard.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.05; duration: 680; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 680; easing.type: Easing.InOutSine }
                      }

                      Image {
                        anchors.centerIn: parent
                        width: Style.space(86)
                        height: Style.space(20)
                        source: root.omarchyLogoSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: 0.82

                        RotationAnimation on rotation {
                          running: thinkingCard.visible
                          loops: Animation.Infinite
                          from: 0
                          to: 360
                          duration: 1450
                        }
                      }
                    }

                    Column {
                      width: parent.width - logoBadge.width - thinkingDots.width - parent.spacing * 2
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)
                      Text {
                        width: parent.width
                        text: "Omarchy is thinking"
                        textFormat: Text.PlainText
                        color: root.aiAccent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        text: "Preparing the next tokens"
                        textFormat: Text.PlainText
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Row {
                      id: thinkingDots
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)
                      Repeater {
                        model: 3
                        delegate: Rectangle {
                          width: Style.space(7)
                          height: width
                          radius: width / 2
                          color: root.aiAccent
                          opacity: 0.28
                          SequentialAnimation on opacity {
                            running: thinkingCard.visible
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 140 }
                            NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 0.28; duration: 420; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: 360 }
                          }
                        }
                      }
                    }
                  }
                }
              }
              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(48)
                visible: root.messages.length === 0
                text: root.ready ? "Ask anything. Attach images, video, audio or files when supported." : "Click Setup and load models before chatting."
                color: Color.muted
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }
          }

          Column {
            id: composer
            width: parent.width
            spacing: Style.space(8)

            Flow {
              width: parent.width
              spacing: Style.space(6)
              visible: root.attachments.length > 0
              Repeater {
                model: root.attachments
                delegate: Button {
                  text: String(modelData.kind || "file").toUpperCase() + " " + String(modelData.label || "attachment")
                  bordered: true
                  foreground: Color.popups.text
                  accent: Color.accent
                  tooltipText: "Click to remove"
                  onClicked: root.removeAttachment(index)
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              TextField {
                id: attachmentField
                width: parent.width - addAttachmentButton.width - parent.spacing
                placeholderText: "Attach path or URL: image, video, audio, PDF, text"
                enabled: root.ready && !root.sending
                onAccepted: root.addAttachment()
              }
              Button {
                id: addAttachmentButton
                text: attachmentField.text.trim() === "" ? "Browse" : "Add file"
                bordered: true
                enabled: attachmentField.enabled
                onClicked: root.addAttachment()
              }
            }

            Row {
              id: inputRow
              width: parent.width
              spacing: Style.space(8)
              TextField {
                id: input
                width: parent.width - sendButton.width
                  - (stopButton.visible ? stopButton.width + parent.spacing : 0)
                  - parent.spacing
                placeholderText: root.ready ? "Message" : "Load models in Setup..."
                enabled: root.ready && !root.sending && root.selectedModel !== ""
                onAccepted: root.sendMessage()
              }
              Button {
                id: sendButton
                text: "Send"
                enabled: input.enabled && (input.text.trim() !== "" || root.attachments.length > 0)
                onClicked: root.sendMessage()
              }
              Button {
                id: stopButton
                text: "Stop"
                bordered: true
                visible: root.sending
                enabled: root.sending
                foreground: Color.urgent
                accent: Color.urgent
                onClicked: root.stopResponse()
              }
            }
          }
        }
      }
    }
  }
}
}
