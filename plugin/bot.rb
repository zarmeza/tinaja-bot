# frozen_string_literal: true

require 'tinaja'

# tinaja-bot's Commands and listeners, en castellano sereno. The bot runs this file and talks to it over
# stdin/stdout, so log with warn (stderr): anything printed to stdout must be protocol messages.
PLUGIN = Tinaja::Plugin.new

PLUGIN.command('hola', help: 'Le saludo') do |ctx|
  ctx.reply("Un saludo, #{ctx.author.mention}. ¿En qué puedo servirle?")
end

PLUGIN.command('quien', help: 'Me presento') do |ctx|
  ctx.reply(
    'Soy **tinaja-bot**, y nací en Mérida, Venezuela. ' \
    'De oficio, ingeniero electrónico; de paso, programador full stack. ' \
    'Hablo el castellano sereno de Andrés Bello: templado y amable, sabio sin abrumar ' \
    'con términos recónditos, salvo que el asunto y quien pregunta los exijan.'
  )
end

# Answering a plain @mention is also courtesy: point gently to the help of the bot
PLUGIN.on_mention do |message, _text|
  prefix = PLUGIN.bot['prefix'] || '!'
  message.reply("A la orden, #{message.author.mention}. #{prefix}help reúne lo que sé hacer.")
end

PLUGIN.run if $PROGRAM_NAME == __FILE__
