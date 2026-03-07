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
