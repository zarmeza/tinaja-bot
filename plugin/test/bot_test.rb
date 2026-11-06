# frozen_string_literal: true

require 'minitest/autorun'
require 'tinaja'
require 'tinaja/testing'
require_relative '../bot'

class BotTest < Minitest::Test
  include Tinaja::Testing

  # No engine in the tests: a dead endpoint makes TinajaLLM.complete answer nil in milliseconds,
  # so the handlers take the "dry tinaja" path — the only behaviour tests can count on
  def setup
    @environment = {
      'TINAJA_LLM_URL' => ENV['TINAJA_LLM_URL'],
      'TINAJA_LLM_MODEL' => ENV['TINAJA_LLM_MODEL'],
      'TINAJA_CHAT_CHANNELS' => ENV['TINAJA_CHAT_CHANNELS'],
    }
    ENV['TINAJA_LLM_URL'] = 'http://127.0.0.1:1/v1/chat/completions'
    ENV.delete('TINAJA_LLM_MODEL')
    ENV.delete('TINAJA_CHAT_CHANNELS')
  end

  def teardown
    @environment.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end

  def test_hola_answers_a_courteous_greeting
    text = run_command(PLUGIN, 'hola').first
    assert_includes text, 'Un saludo, <@1>'
    assert_includes text, '¿En qué puedo servirle?'
  end

  def test_quien_presents_the_bot_without_announcing_its_virtues
    text = run_command(PLUGIN, 'quien').first
    assert_includes text, 'Mérida, Venezuela'
    assert_includes text, 'ingeniero electrónico'
    # A wise and gentle voice doesn't have to say it is wise and gentle; it just is
    ['sabio', 'sereno', 'calmo', 'gentil', 'Bello'].each do |word|
      refute_includes text.downcase, word
    end
  end

  def test_hable_converses_and_answers_in_the_bot_voice_when_the_engine_is_dry
    text = run_command(PLUGIN, 'hable').first
    assert_equal TinajaLLM::DRY_TINAJA, text
  end

  def test_mention_answers_in_the_bot_voice_when_the_engine_is_dry
    actions = run_event(PLUGIN, { 'type' => 'mention', 'message' => fake_message('<@42> hola', id: '5'), 'text' => 'hola' })
    assert_equal 1, actions.size
    assert_equal TinajaLLM::DRY_TINAJA, actions.first['content']
    assert_equal '5', actions.first['reply_to']
  end

  def test_mention_stays_silent_in_an_uninvited_conversation_channel
    ENV['TINAJA_CHAT_CHANNELS'] = '77'
    actions = run_event(PLUGIN, { 'type' => 'mention', 'message' => fake_message('<@42> hola', id: '5', channel_id: '77'), 'text' => 'hola' })
    assert_empty actions
  end

  def test_message_answers_when_the_channel_was_lent
    ENV['TINAJA_CHAT_CHANNELS'] = '77'
    message = fake_message('buenos días a la tinaja', id: '9', channel_id: '77')
    actions = run_event(PLUGIN, { 'type' => 'message', 'message' => message })
    assert_equal 1, actions.size
    assert_equal TinajaLLM::DRY_TINAJA, actions.first['content']
  end

  def test_command_messages_in_the_lent_channel_keep_their_silence
    ENV['TINAJA_CHAT_CHANNELS'] = '77'
    # the host speaks first in a real run: the hello introduces the bot (name, prefix, id)
    run_event(PLUGIN, { 'type' => 'hello', 'protocol' => 1, 'bot' => { 'prefix' => '!' } })
    message = fake_message('!ping', id: '9', channel_id: '77')
    actions = run_event(PLUGIN, { 'type' => 'message', 'message' => message })
    assert_empty actions
  end

  def test_turns_carry_the_channel_chatter_and_the_current_ask
    author = fake_author('jane')
    history = [Tinaja::Message.new(fake_message('antes hice una pregunta larga que ya pasó de moda', id: '1', author: author), nil),
               Tinaja::Message.new(fake_message('¿y esta tinaja cómo funciona?', id: '2', author: author), nil)]
    current = Tinaja::Message.new(fake_message('pero really, ¿sirve?', id: '2', channel_id: '10', author: author), nil)
    turns = TinajaLLM.turns(history, current_message: current, user_text: 'pero really, ¿sirve?')

    assert_equal 2, turns.size
    # the current ask (the channel's last line) must be the last turn, not an echo of the chatter
    assert_includes turns.first['content'], 'antes hice una pregunta larga que ya pasó de moda'
    assert_equal 'jane: pero really, ¿sirve?', turns.last['content']
    refute_includes turns.last['content'], 'antes hice'
  end
end
