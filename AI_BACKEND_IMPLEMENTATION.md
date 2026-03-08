# AI Backend Implementation Notes

Read this before changing:
- `/Users/kientran/Desktop/KiensApps/Tab Note/Tab Note/AIService.swift`
- `/Users/kientran/Desktop/KiensApps/Tab Note/Tab Note/SettingsManager.swift`
- `/Users/kientran/Desktop/KiensApps/Tab Note/Tab Note/SettingsView.swift`
- `/Users/kientran/Desktop/KiensApps/Tab Note/Tab Note/NoteEditorView.swift`

This document exists because the AI backend went through several incorrect iterations. The same mistakes are easy to repeat if someone only looks at the current UI and assumes the backend is generic.

## Current truth

- Local and API are separate persisted configurations. Do not merge them back together.
- API mode supports two protocol families:
  - OpenAI-compatible
  - Anthropic-compatible
- Transport is inferred from the endpoint:
  - endpoints containing `/anthropic` use the Anthropic-compatible path
  - everything else uses the OpenAI-compatible path
- API diagnostics must test the real request path, not a generic health endpoint.
- Inline AI popup output must hide provider reasoning/thinking text and only show the final visible answer.
- API mode supports saved profiles that store endpoint, header, key, and model together for quick switching.
- OpenAI-compatible payloads are not fully uniform across model families; GPT-5-family models need `max_completion_tokens` instead of `max_tokens`.
- OpenAI-compatible GPT-5/reasoning-family models also reject custom sampling fields like `temperature`; omit them and let the provider use its default.
- API mode now also supports an Advanced JSON mode that bypasses built-in provider mapping entirely.
- Advanced JSON mode owns the full request shape:
  - endpoint
  - headers
  - JSON body template
  - response text path
  - optional streaming path/prefix/done token
- Advanced JSON mode is intentionally not a thin wrapper around OpenAI-compatible assumptions. Do not inject provider-specific fields into it.
- Advanced JSON mode supports placeholder replacement for runtime values such as `{{system_prompt}}`, `{{user_message}}`, `{{stream}}`, `{{temperature}}`, `{{max_tokens}}`, and `{{max_completion_tokens}}`.
- Prompt injection presets only affect Advanced JSON mode when the JSON body actually uses placeholders like `{{system_prompt}}` and `{{user_message}}`; hardcoded messages bypass them.
- If `response.text_path` is omitted, the app may auto-detect common OpenAI/Anthropic response shapes, but it should never dump raw JSON into the inline AI popup as a fallback.
- Console logs like `stalled, attempting fallback` and `NSURLErrorDomain -1005` can come from CFNetwork transport fallback even when the provider request eventually works. Do not immediately treat them as payload-shape bugs.
- JSON mode should still surface the real model name from `body.model` for inline metrics; using a placeholder label like `Custom JSON` hides pricing/routing context and makes speed-cost debugging misleading.
- Inline popup markdown rendering should stay active during streaming, not only after completion, or providers that emit bold Markdown incrementally will look visually downgraded compared with the standard adapters.

## Known-good fast preset

User-confirmed fast OpenAI setup for GPT-5 Nano:
- Advanced JSON mode
- endpoint: `/v1/responses`
- streaming enabled
- streamed text extracted from the event `delta`
- low latency achieved with `reasoning.effort: "minimal"`

What to preserve around it:
- keep `{{system_prompt}}` and `{{user_message}}` placeholders in the JSON body so prompt presets still flow into the request
- keep markdown-friendly inline prompts, because GPT-5 Nano can answer quickly but otherwise tends to flatten headings/labels more than some other providers
- keep the popup's markdown renderer active while streaming so `**Bold labels**` show up as soon as the closing marker arrives

## Implementation iterations

### Iteration 1: Shared Local/API fields

Wrong assumption:
- One endpoint field and one model field could be reused for both Local and API if the labels changed with the toggle.

Why it failed:
- Users expected Local and API to be independently configurable.
- Switching modes silently changed the meaning of the same stored values and caused setup confusion.

Current rule:
- Keep separate persisted values for:
  - Local endpoint
  - Local model
  - API endpoint
  - API model
  - API key
  - API header

### Iteration 7: JSON mode as a real bypass

Wrong assumption:
- Advanced configuration could stay as a future idea while the built-in provider adapters kept covering most users.

Why it failed:
- Users who work from provider docs or custom gateways do not want backend inference or hidden parameter mutation.
- The built-in adapters still expose transport-specific assumptions like token fields or sampling rules.

Current rule:
- JSON mode is a first-class request path.
- When JSON mode is selected, the app should execute the pasted JSON request definition after placeholder replacement and should not reshape it into OpenAI-compatible or Anthropic-compatible payloads.
- When users hardcode `"messages"` content in the JSON body, that is the final request content. Prompt injection presets are only applied through placeholders.

### Iteration 8: Treating streamed text as plain text

Wrong assumption:
- The inline popup could render streamed content as a plain string first and only apply markdown styling after completion.

Why it failed:
- Fast providers and low-latency JSON presets make the streaming state the dominant visible state.
- If streamed content contains Markdown like `**Heading**`, plain-text rendering makes the fast path look visually worse than slower providers even though the payload is correct.

Current rule:
- Use the same manual markdown rendering pipeline for streamed visible text and completed text.
- Keep the special placeholder styling only for the empty `Thinking...` state.

### Iteration 2: Hardcoded `Authorization`

Wrong assumption:
- Every API-compatible provider would accept a hardcoded `Authorization` header with the same formatting.

Why it failed:
- Some providers need configurable header names or compatible fallback behavior.

Current rule:
- Header name is user-configurable.
- If the header is `Authorization`, the app auto-adds `Bearer ` when needed.
- If the header is `x-api-key`, the app sends the raw key.

### Iteration 3: Treating every API endpoint as OpenAI-compatible

Wrong assumption:
- Any custom API base could be handled with OpenAI `/chat/completions`.

Why it failed:
- Anthropic-compatible providers need `/v1/messages`, different headers, and different response parsing.

Current rule:
- `/anthropic` endpoints use:
  - path: `/v1/messages`
  - header: `anthropic-version: 2023-06-01`
  - fallback auth: `x-api-key` is added from the raw key when needed
- non-`/anthropic` endpoints use:
  - path: `/chat/completions`

### Iteration 4: Diagnosing APIs via `/models`

Wrong assumption:
- `GET /models` was a safe universal connectivity test for API providers.

Why it failed:
- On March 7, 2026, live MiniMax probing showed:
  - `https://api.minimax.io/v1/chat/completions` worked
  - `https://api.minimax.io/v1/models` returned `404`
- That made the app report “failed” even though actual generation worked.

Current rule:
- API diagnostics must perform a tiny real completion request against the active protocol.
- Do not use `/models` as the sole success criterion for API mode.

### Iteration 5: Assuming auth was still broken after DeepSeek worked

Wrong assumption:
- If MiniMax still failed after DeepSeek worked, the remaining issue must still be auth formatting.

Why it failed:
- The remaining failure was the diagnostic endpoint, not the auth header used for real requests.

Current rule:
- When one provider works and another fails, compare:
  - protocol family
  - request path
  - diagnostics path
  - streamed response shape
- Do not jump straight to “bad API key” unless a live probe or saved-config inspection supports it.

### Iteration 6: Showing provider reasoning in the popup

Wrong assumption:
- The streamed `content` field could be shown directly to the user.

Why it failed:
- Some providers, including MiniMax, can stream hidden reasoning blocks such as `<think>...</think>` before the final answer.
- That makes the popup show internal reasoning instead of the user-facing response.

Current rule:
- Strip hidden reasoning blocks before rendering streamed or completed text.
- Handle both:
  - complete tagged blocks like `<think>...</think>`
  - incomplete streamed blocks where `<think>` has arrived but `</think>` has not yet arrived

## Provider rules

### OpenAI-compatible

Use when endpoint does not contain `/anthropic`.

Request path:
- `/chat/completions`

Typical providers:
- OpenAI-compatible services
- DeepSeek
- MiniMax OpenAI-compatible base such as `https://api.minimax.io/v1`

Notes:
- MiniMax has been confirmed to accept `Authorization: Bearer ...` on the OpenAI-compatible completion path.
- Do not assume `/models` is available just because `/chat/completions` works.
- Do not assume `max_tokens` works for every OpenAI-compatible model; GPT-5-family models require `max_completion_tokens`.

### Anthropic-compatible

Use when endpoint contains `/anthropic`.

Request path:
- `/v1/messages`

Headers:
- `anthropic-version: 2023-06-01`
- configured auth header
- `x-api-key` fallback from the raw key when needed

Typical providers:
- Anthropic-compatible services
- MiniMax Anthropic-compatible base such as `https://api.minimax.io/anthropic`

## Inline popup rules

- Keep the borderless shared popup architecture.
- Keep prompt replay and follow-up behavior.
- Keep streamed partial updates.
- Do not show provider reasoning blocks to the user.
- Cost, tokens, and speed can be derived heuristically in the popup UI, but the answer body must only contain visible response text.

## API preset rules

- Saved API settings are full profiles, not just model aliases.
- A saved profile includes:
  - display name
  - endpoint
  - API key
  - header name
  - model
- Selecting a saved profile must load the full API configuration into the active API fields.
- Keep explicit save/update/delete actions so switching profiles does not silently overwrite another saved setup.

## Do not regress these

- Do not collapse Local and API settings into shared fields again.
- Do not remove protocol inference for `/anthropic`.
- Do not replace real API diagnostics with `/models`.
- Do not hardcode one auth header shape for every provider.
- Do not render `<think>` or similar hidden reasoning in the popup.
- Do not reduce saved API profiles to a single model dropdown that loses endpoint/header/key context.
