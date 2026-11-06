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
      'TINAJA_BRAVE_API_KEY' => ENV['TINAJA_BRAVE_API_KEY'],
    }
    ENV['TINAJA_LLM_URL'] = 'http://127.0.0.1:1/v1/chat/completions'
    ENV.delete('TINAJA_LLM_MODEL')
    ENV.delete('TINAJA_CHAT_CHANNELS')
    ENV.delete('TINAJA_BRAVE_API_KEY')
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

  # The lamp (TinajaSearch) is stubbed out: tests never touch the live web
  def test_a_confident_answer_needs_no_lamp
    passes = []
    TinajaSearch.stub(:results, ->(_q) { flunk 'the lamp must not light for known matters' }) do
      TinajaLLM.stub(:complete, lambda { |turns|
        passes << turns.first['content']
        'Castellano sereno y fiel.'
      }) do
        answer = TinajaLLM.complete_with_search([{'role' => 'user', 'content' => 'Eleazar: ¿quién eres?'}])
        assert_equal 'Castellano sereno y fiel.', answer
      end
    end
    assert_equal [TinajaLLM::FIRST_PASS_PROMPT], passes.uniq # one pass and no more
  end

  def test_a_doubtful_answer_receives_the_web_and_answers_upon_it
    passes = []
    queries = []
    TinajaSearch.stub(:results, lambda { |query|
      queries << query
      [['El tiempo en Mérida', 'https://tiempo.example/merida', 'Chubasco por la tarde.']]
    }) do
      TinajaLLM.stub(:complete, lambda { |turns|
        system = turns.first['content']
        if system.include?('Ya se averiguó algo en la web')
          passes << system
          'Según lo que hoy dice la red, chubasco por la tarde en Mérida; el sitio es tiempo.example.'
        elsif system == TinajaLLM::FIRST_PASS_PROMPT
          "Del cielo de hoy mejor me callaría.\nNECESITO_AVERIGUAR: clima hoy en Mérida"
        else
          flunk 'the second pass must carry the web findings'
        end
      }) do
        answer = TinajaLLM.complete_with_search([{'role' => 'user', 'content' => 'Eleazar: ¿llueve en Mérida hoy?'}])
        assert_includes answer, 'chubasco por la tarde'
        refute_includes answer, 'NECESITO_AVERIGUAR' # the seal is never shown
      end
    end
    assert_equal ['clima hoy en Mérida'], queries
    assert_equal [TinajaLLM::SECOND_PASS_PROMPT], passes.uniq
  end

  def test_a_blind_lamp_lets_the_engine_confess_instead_of_inventing
    TinajaSearch.stub(:results, ->(_q) { nil }) do
      TinajaLLM.stub(:complete, lambda { |turns|
        if turns.first['content'].include?('Ya se averiguó algo en la web')
          # the findings turn (only the confession note) reached it; its answer still advances
          'La red no me dejó verla, y no voy a inventar: mañana con mejor lámpara.'
        else
          "Ni idea del asunto, de verdad.\nNECESITO_AVERIGUAR: la libra hoy"
        end
      }) do
        answer = TinajaLLM.complete_with_search([{'role' => 'user', 'content' => 'Eleazar: ¿y la libra?'}])
        assert_equal 'La red no me dejó verla, y no voy a inventar: mañana con mejor lámpara.', answer
      end
    end
  end

  def test_the_dry_engine_stays_dry_through_the_lamp
    # dead endpoint: pass one answers nil, and the whole turn answers nil (no lamp is lit for it)
    assert_nil TinajaLLM.complete_with_search([{'role' => 'user', 'content' => 'Eleazar: ¿quién eres?'}])
  end

  def test_the_web_reads_brave_json_undefiled
    body = '{"web":{"results":[' \
           '{"title":"El tiempo en <b>Mérida</b>","url":"https://tiempo.example/merida","description":"Chubasco por la tarde, <b>según</b> su informe."},' \
           '{"title":"","url":"https://tiempo.example/nada"}' \
           "]}}"
    findings = TinajaSearch.parse(body)
    assert_equal 1, findings.size # the untitled finding doesn't make it to the lantern
    title, href, snippet = findings.first
    assert_equal 'El tiempo en Mérida', title
    assert_equal 'https://tiempo.example/merida', href
    assert_equal 'Chubasco por la tarde, según su informe.', snippet
  end

  def test_the_lamp_stays_dark_without_a_key
    refute TinajaSearch.results('clima hoy en Mérida') # nil: neither findings nor a crash
  end
end
