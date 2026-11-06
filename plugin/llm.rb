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
require_relative 'search'

module TinajaLLM
  DEFAULT_URL = 'http://127.0.0.1:11434/v1/chat/completions'
  DEFAULT_MODEL = 'qwen2.5:3b'
  MAX_TOKENS = 200
  HISTORY_LIMIT = 12
  TRANSCRIPT_CHARS = 2000
  DRY_TINAJA = 'La tinaja está seca: no consigo hablar con su motor. Vuelva más tarde, que aquí quedo.'
  WEB_BLIND = 'Busqué aclararlo en la red y la red no se me dejó ver: le hablo de eso cuando tenga corcho.'
  MARKER = 'NECESITO_AVERIGUAR'
  QUERY_CHARS = 120
  MAX_FINDINGS = 5
  FINDING_CHARS = 240

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

  # The rules of the first pass, where the engine confesses what only this morning's world knows.
  # The marker is a private seal between jar and lamp: the Members never see it — pass_one scrapes it
  # off whatever the engine answers
  FIRST_PASS_PROMPT = SYSTEM_PROMPT + ' ' \
    'Cada respuesta, responda de tu propio saber cuando tu saber paresca bastante. Si pregunta lo que ' \
    'el mundo decidió desde de ti — fechas nuevas, nombres del día, precios, lo que no puede todavía ' \
    'saberte — no respondas a lo tonto: termina tu respuesta con una sola línea ' \
    "\n#{MARKER}: <lo que hay que averiguar en la web, en pocas palabras>\n" \
    'y nada más después de ella. Fuera de esa línea no menciones que puedes averiguar'

  SECOND_PASS_PROMPT = SYSTEM_PROMPT + ' ' \
    'Ya se averiguó algo en la web para esta pregunta: abajo, lo que se alcanzó. Apóyate en ello en ' \
    'lugar de tu propio saber, y deja ver de qué sitio viene lo que asientes. No leas nada en ello ' \
    'que no esté escrito: si la averiguación fue pobre, confiéncelo y responde de lo tuyo.'

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

  # One conversation turn, with the day-lamp in it. First pass: the engine answers of his own
  # knowledge, or seals his answer with the MARKER and the query for a web scolding. When he does,
  # the findings go in as one more turn and the second pass answers with them under his hand —
  # falter included, so he confesses instead of inventing. Returns the answer text, or nil when the
  # engine (not the lamp) is unreachable: the caller answers in the bot's own voice
  def complete_with_search(turns)
    probe = complete([{'role' => 'system', 'content' => FIRST_PASS_PROMPT}] + turns)
    return nil if probe.nil?

    query = seal_of(probe)
    return porcelain(probe) unless query

    answer = complete([{'role' => 'system', 'content' => SECOND_PASS_PROMPT}] + turns + [findings_turn(query, TinajaSearch.results(query))])
    answer || WEB_BLIND
  end

  # What could be of today's world: the line the engine pledged with, or nil on a free answer
  def seal_of(probe)
    match = probe.match(/\n?#{MARKER}: *(.+)/)
    return nil unless match

    query = match[1].gsub(/[«"“”']/, '').strip.slice(0, QUERY_CHARS)
    query.empty? ? nil : query
  end

  # The answer to show: without the seal, and with any afterthought the engine left behind him
  def porcelain(probe)
    probe.sub(/#{MARKER}.*\z/m, '').gsub(/\n{3,}/, "\n\n").strip
  end

  # The web's findings as one more turn, phrased so the engine can also confess a poor haul
  def findings_turn(query, results)
    text =
      if results.nil? || results.empty?
        "Busqué «#{query}» en la web y no me entregó nada útil: la lámpara quedó seca. " \
        'Con eso por debajo, responde de tu propio saber y DECLÁRALO; si no tienes nada fiable, ' \
        'dilo sin rodeos y no inventes.'
      else
        lines = results.take(MAX_FINDINGS).map do |title, href, snippet|
          "• #{title}\n  #{href}\n  #{snippet.to_s.slice(0, FINDING_CHARS)}"
        end
        "Esto es lo que la web dice ahora mismo de «#{query}» (un resumen, y el resumen puede errar):\n" +
          lines.join("\n") + "\n" \
          'Apóyate en esto en lugar de tu saber viejo; deja ver de qué sitio viene lo que asientes.'
      end
    {'role' => 'user', 'content' => text}
  end
end
