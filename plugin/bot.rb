# frozen_string_literal: true

require 'tinaja'
require_relative 'llm'

# tinaja-bot's Commands and listeners, en castellano sereno. The bot runs this file and talks to it over
# stdin/stdout, so log with warn (stderr): anything printed to stdout must be protocol messages.
# The conversation convention, from the plugin protocol up: speak when addressed — an on_mention from any
# Member anywhere, the !hable Command, or an uninvited chat in TINAJA_CHAT_CHANNELS; quiet elsewhere.
PLUGIN = Tinaja::Plugin.new

PLUGIN.command('hola', help: 'Le saludo') do |ctx|
  ctx.reply("Un saludo, #{ctx.author.mention}. ¿En qué puedo servirle?")
end

PLUGIN.command('quien', help: 'Me presento') do |ctx|
  ctx.reply(
    '**tinaja-bot**, nacido en Mérida, Venezuela. ' \
    'De profesión, ingeniero electrónico; también programo para la web: tanto lo que se ve en la ' \
    'pantalla como lo que corre en el servidor. ' \
    'Una tinaja es apenas una vasija de barro que conserva el agua fresca y la sirve a su tiempo; ' \
    'así prefiero trabajar. Para lo que necesite, aquí me tiene.'
  )
end

PLUGIN.command('hable', help: 'Converse conmigo sin señas: !hable [algo]') do |ctx|
  text = ctx.args.join(' ').strip
  converse(ctx.message, text.empty? ? 'Doy la palabra: ¿de qué habla hoy?' : text)
end

# A plain @mention anywhere is the address; the channels of TINAJA_CHAT_CHANNELS already answered it
PLUGIN.on_mention do |message, text|
  next if TinajaLLM.chat_channels.include?(message.channel_id)

  converse(message, text)
end

# Uninvited, only where the owner lent tinaja-bot the floor: Commands keep their protocol answer
PLUGIN.on_message do |message|
  next unless TinajaLLM.chat_channels.include?(message.channel_id)
  next if PLUGIN.bot['prefix'] && message.content.lstrip.start_with?(PLUGIN.bot['prefix'])

  converse(message, message.content)
end

# One turn of conversation: the channel's recent chatter for context, the engine for prose, and the
# bot's own voice when the engine fails (an unspecified failure never shows a stacktrace in a channel)
def converse(message, user_text)
  history = PLUGIN.history(message.channel_id, TinajaLLM::HISTORY_LIMIT)
  turns = TinajaLLM.turns(history, current_message: message, user_text: user_text)
  answer = TinajaLLM.complete_with_search(turns)
  message.reply(answer || TinajaLLM::DRY_TINAJA)
rescue StandardError => e
  warn "tinaja-bot: conversation failed: #{e.class}: #{e.message}"
  message.reply(TinajaLLM::DRY_TINAJA)
end

PLUGIN.run if $PROGRAM_NAME == __FILE__
