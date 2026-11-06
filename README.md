# tinaja-bot

**A Discord bot from Mérida, Venezuela, that speaks castellano in the line of Andrés Bello.**

> Una tinaja es apenas una vasija de barro que conserva el agua fresca y la sirve a su tiempo.

tinaja-bot is not a command wrapper with canned replies. Its conversations run on a local LLM
([Ollama](https://ollama.com) by default), so it can follow the thread of a channel without shipping
the conversation itself to a third-party API. When its training runs out — today's dollar rate, the
sky over Mérida, who won last night's match — it admits it privately, consults the open web, and
answers with the source in hand. The everyday sources need no API keys, and all of them were checked
from Venezuela without a VPN or a browser CAPTCHA in the way.

## What it does

- **Converses in castellano**, whichever language it is addressed in. The persona is calm, gentle and
  precise: an electronic engineer from Mérida who also writes for the web. It lives in `CONTEXT.md`
  and in the system prompt in `plugin/llm.rb`.
- **Knows when it does not know.** The first pass either answers from its own knowledge or ends with
  a private `NECESITO_AVERIGUAR: <query>` seal. The seal never reaches Discord: the bot uses it to
  fetch the day's facts and then answers a second time, citing what it found.
- **Speaks when addressed.** Mentions work anywhere; `!hable` opens a conversation explicitly; and
  channels lent through `TINAJA_CHAT_CHANNELS` get uninvited replies. DMs work the same way once
  their channel id is lent.
- **Remembers the room, not itself.** Each turn carries the channel's recent chatter as context,
  capped so a long conversation does not become an infinite prompt.
- **Fails in character.** If the engine is down, the channel sees *“La tinaja está seca…”*, never a
  stack trace. If the web haul is thin, the bot confesses instead of inventing.

## How to talk to it

| Where | What to do |
|---|---|
| Any server channel | `@tinaja-bot <your question>` |
| Any server channel | `!hable <your question>` |
| A lent channel or DM | Write normally — no prefix, no mention |
| Commands | `!hola`, `!quien`, `!ping`, `!glossary [term]`, `!help` |

`!hable` is the explicit door: it starts a conversation even in a channel that was not lent to the
bot. The `!` prefix belongs to Commands, so something like `!buenos días` is parsed as an unknown
Command rather than chat; use `!hable` for free-form prose.

Plain DM messages are answered when the DM channel's id is in `TINAJA_CHAT_CHANNELS`. The framework's
message payload does not yet say whether a channel is a DM, so this is the current workaround; `!hable`
works in a DM even without it.

## The day-lamps: web without keys

The local model's knowledge froze when it was trained. For what the world decided since, the bot has a
small ladder of **day-lamps**. The first pass asks the engine; if the engine seals the answer with
`NECESITO_AVERIGUAR`, the lamps fetch, the findings go back as one more turn, and the second pass
answers from them. The answer is asked to name its source; a poor haul is confessed instead of filled
with invention, and a failed second pass falls back to the bot's `WEB_BLIND` line.

| Ask | Lamp | Source |
|---|---|---|
| Dollar, euro, the street's rate | `dolarapi.com` | Venezuela's official and parallel rates |
| Weather, rain, temperature | Open-Meteo | The sky of Mérida (`TINAJA_HOME_LAT`/`TINAJA_HOME_LON` to relocate) |
| Today's news, names, results | Google News RSS | The day's castellano coverage, with links |
| The wider web | Bing RSS | Everything the news feed does not cover |

The order is: the trade lamps first; then Brave Search (when `TINAJA_BRAVE_API_KEY` is set); then the
owner's own SearXNG (when `TINAJA_SEARX_URL` is set); then Google News RSS; then Bing RSS. Brave is
geographically blocked from Venezuela for now and is kept for the day the map moves; the keyless lamps
are the ones that actually answer here.

The public search-engine routes were tried and rejected: DuckDuckGo serves a CAPTCHA, Mojeek returns
403, and the public SearXNG instances are either rate-limited or behind an antibot page. RSS feeds and
plain APIs are the honest path for a program; scraping a search page is not.

## Quick start

You need [uv](https://docs.astral.sh/uv/getting-started/installation/), Ruby 3.4 or newer, and
[Ollama](https://ollama.com) on the machine that will run the bot.

```bash
uv sync
(cd plugin && bundle install)

cp env.sample .env
# edit .env and set DISCORD_BOT_TOKEN

ollama pull qwen2.5:3b
uv run tinaja-bot run
```

Then invite the bot to a server and say `@tinaja-bot hola`, or send it `!hable hola` in a DM. The
first reply may take a few seconds while the model loads; later turns are faster.

To point the bot at an Ollama instance on another machine — or at the host from inside Docker — set
`TINAJA_LLM_URL`, for example `http://192.168.1.10:11434/v1/chat/completions`.

## Configuration

All settings are environment variables, read from `.env` at startup. The token is the only secret;
the plugin process never sees it.

| Variable | Default | Purpose |
|---|---|---|
| `DISCORD_BOT_TOKEN` | — | **Required.** The bot token from the Discord developer portal. |
| `TINAJA_LLM_URL` | `http://127.0.0.1:11434/v1/chat/completions` | OpenAI-compatible endpoint (Ollama by default). |
| `TINAJA_LLM_MODEL` | `qwen2.5:3b` | Model name. A larger model is the straightforward upgrade when the 3B one feels thin. |
| `TINAJA_CHAT_CHANNELS` | unset (mentions only) | Comma- or space-separated channel ids where the bot converses without being addressed. DM channel ids work too. |
| `TINAJA_HOME_LAT` | `8.6047` | Latitude for the weather lamp. |
| `TINAJA_HOME_LON` | `-71.1476` | Longitude for the weather lamp. |
| `TINAJA_BRAVE_API_KEY` | unset | Optional Brave Search key; jumps ahead of the public feeds while its quota lasts. |
| `TINAJA_SEARX_URL` | unset | Optional SearXNG base URL (JSON format required); jumps ahead of the public feeds. |

`.env` is ignored by git. `env.sample` documents every switch and is safe to commit.

## Under the hood

The Discord connection is Python; the bot's own code is Ruby. That split is the framework's design,
not an accident:

```
Discord  <— Gateway —>  Python host (tinaja-bot-base)
                              │  JSON lines over stdin/stdout
                              ▼
                       Ruby plugin (plugin/bot.rb)
```

- `bot.toml` — name, prefix, intents, plain-text replies, mention behaviour, and how the host starts
  the plugin.
- `CONTEXT.md` — the server's lexicon and the bot's persona, answered by `!glossary [term]`.
- `plugin/bot.rb` — Commands and listeners: `!hola`, `!quien`, `!hable`, mention handling and the
  conversation turn.
- `plugin/llm.rb` — the local engine, the two-pass web protocol, the transcripts and the bot's voice
  when the engine fails.
- `plugin/search.rb` — the day-lamps and their common findings format.
- `plugin/test/` — the test suite; every network call is stubbed, so tests never leave the machine.

The host and the Ruby SDK both come from
[tinaja-bot-base](https://github.com/xionjames/tinaja-bot-base), pinned to `main` in `pyproject.toml`
and `plugin/Gemfile`. The only runtime gem added beyond the SDK is `rexml`, for reading RSS feeds now
that Ruby 4 no longer ships it as a default gem.

## Tests

```bash
cd plugin
bundle exec rake test
```

The suite covers the conversation wiring, the seal/second-pass protocol, the trade classification, the
money and weather parsers, the RSS readers, and the ladder order. It uses no real network.

## Docker and CI

```bash
uv run tinaja-bot check     # is the bot ready to build?
uv run tinaja-bot build     # tags ghcr.io/zarmeza/tinaja-bot:latest and :<git sha>
docker run -it --env-file .env ghcr.io/zarmeza/tinaja-bot:latest
uv run tinaja-bot publish   # docker push; log in to ghcr.io first
```

The image builds on Linux, so the gem lockfile carries `x86_64-linux` and `aarch64-linux`. Pushing to
`main` runs `.github/workflows/build-and-push.yaml`: it runs the tests and `tinaja-bot check` first,
then publishes a multi-arch image to `ghcr.io/zarmeza/tinaja-bot`.

## Known edges

- **No typing indicator yet.** Protocol v1 has no primitive for it; the Python host owns the Discord
  connection, and the plugin has no protocol action to ask for it. Filed upstream as
  [tinaja-bot-base#6](https://github.com/xionjames/tinaja-bot-base/issues/6); the bot side is ready to
  wire it when the framework lands it.
- **DMs need their channel id lent.** The protocol does not yet carry a DM flag; `TINAJA_CHAT_CHANNELS`
  is the bridge. `!hable` works in a DM regardless.
- **The 3B model is small.** It is fast on a CPU-only laptop and good enough for conversation, but it
  is not a world expert. `TINAJA_LLM_MODEL` is the one-line upgrade path.
- **Brave is unreachable from Venezuela.** The key rung exists for other networks; the keyless lamps
  are the ones this bot relies on.
- **Unknown `!` Commands are noisy.** The framework logs `CommandNotFound` as an ERROR while the
  fallback reply still goes out. Members see the reply, not the stack trace.

## Name

A *tinaja* is a clay jar that keeps water cool and serves it calmly. The bot carried the nickname
*gocho* — the traditional name for someone from Mérida — until it settled on the thing it actually
does: hold the conversation, keep it fresh, serve it when asked.
