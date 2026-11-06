# frozen_string_literal: true

# The local engine behind tinaja-bot's conversations: an OpenAI-compatible endpoint (Ollama by
# default) reached with the Ruby standard library, so the image needs no new gems.
# Endpoint, model and the uninvited-conversation channels come from the environment, the way the
# framework passes it to Plugins (everything except DISCORD_BOT_TOKEN):
#   TINAJA_LLM_URL        default: Ollama on this machine
#   TINAJA_LLM_MODEL      default: a small castellano-strong instruct model
#   TINAJA_CHAT_CHANNELS  optional, comma-separated channel ids where he speaks without being addressed
require 'json'
require 'net/http'

module TinajaLLM
  DEFAULT_URL = 'http://127.0.0.1:11434/v1/chat/completions'
  DEFAULT_MODEL = 'qwen2.5:3b'
  MAX_TOKENS = 200
  HISTORY_LIMIT = 12
  TRANSCRIPT_CHARS = 2000
  DRY_TINAJA = 'La tinaja está seca: no consigo hablar con su motor. Vuelva más tarde, que aquí quedo.'

  # Who tinaja-bot is, told to the engine, not to the people: the character shows, it doesn't announce
  SYSTEM_PROMPT =
    'Habla como tinaja-bot, un bot de Discord para una comunidad de habla castellana. Sigue en la ' \
    'lengua la línea de Andrés Bello: correcto, templado y amable; no digas que eres sabio ni ' \
    'templado: hazlo. Naciste en Mérida, Venezuela; eres ingeniero electrónico y programas para la ' \
    'web, de lo que se ve en la pantalla a lo que corre en el servidor. Responde con pocas palabras, ' \
    'sin tecnicismos gratuitos; si el asunto los requiere, explícalos con transparencia, como quien ' \
    'explica a un colega. No inventes datos sobre personas del canal ni prometas lo que el bot no ' \
    'puede hacer: indica el camino exacto de lo que sí puedes. Nombres como los que ves antes de ' \
    'cada mensaje identifican a quien escribe del canal; no dirijas a otro lo que te dijeron a ti. ' \
    'Responde siempre en castellano, sea cual fuere la lengua del mensaje: si te escriben en ' \
    'portugués, en inglés o en otra lengua, respóndeles igualmente en castellano.'

  module_function

  # Env vars win with truth; a present-but-empty value falls back to the default
  def endpoint
    value = ENV['TINAJA_LLM_URL']
    value && !value.empty? ? value : DEFAULT_URL
  end

  def model
    value = ENV['TINAJA_LLM_MODEL']
    value && !value.empty? ? value : DEFAULT_MODEL
  end

  def chat_channels
    (ENV['TINAJA_CHAT_CHANNELS'] || '').split(/[\s,]+/).reject(&:empty?)
  end

  # The turns for the engine: the channel's recent chatter (as who-said-what, capped from the
  # oldest), still without the current message, which arrives as its own turn
  def turns(history, current_message:, user_text:)
    past = history
            .reject { |message| message.id == current_message.id }
            .map { |message| { 'role' => 'user', 'content' => "#{message.author.display_name}: #{message.content}" } }
    past.shift while past.sum { |turn| turn['content'].length } > TRANSCRIPT_CHARS && past.size > 2
    past + [{ 'role' => 'user', 'content' => "#{current_message.author.display_name}: #{user_text}" }]
  end

  # One conversation turn against the engine. Returns the answer text, or nil when the engine is
  # unreachable, slow to open, unhappy or silent: the caller then answers in the bot's own voice
  def complete(turns)
    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate('model' => model, 'messages' => turns, 'max_tokens' => MAX_TOKENS, 'temperature' => 0.7)
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, write_timeout: 5, read_timeout: 180) do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    answer = JSON.parse(response.body)&.dig('choices', 0, 'message', 'content')&.to_s&.strip
    answer&.empty? ? nil : answer
  rescue StandardError => e
    warn "tinaja-bot: the engine failed: #{e.class}: #{e.message}"
    nil
  end
end
