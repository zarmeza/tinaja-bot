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
      'TINAJA_SEARX_URL' => ENV['TINAJA_SEARX_URL'],
    }
    ENV['TINAJA_LLM_URL'] = 'http://127.0.0.1:1/v1/chat/completions'
    ENV.delete('TINAJA_LLM_MODEL')
    ENV.delete('TINAJA_CHAT_CHANNELS')
    ENV.delete('TINAJA_BRAVE_API_KEY')
    ENV.delete('TINAJA_SEARX_URL')
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

  def test_the_money_lamp_reads_both_rates_the_official_first
    entries = JSON.parse('[' \
      '{"nombre":"Dólar","fuente":"oficial","promedio":896.1225,"fechaActualizacion":"2026-11-06T00:00:00-04:00"},' \
      '{"nombre":"Paralelo","fuente":"paralelo","promedio":1009.952417,"fechaActualizacion":"2026-11-06T17:01:00"}]')
    findings = TinajaSearch.findings_money(entries, 'https://ve.dolarapi.com/v1/dolares', 'Dólar')
    assert_equal ['Dólar oficial en Venezuela: 896,12 Bs', 'Dólar paralelo en Venezuela: 1.009,95 Bs'],
                 findings.map { |finding| finding[0] }
    assert_includes findings.first[2], 'fuente: oficial'
  end

  def test_the_clima_lamp_reads_the_sky_of_merida
    body = JSON.parse('{"current":{"temperature_2m":22.0,"precipitation":0.0,"weather_code":3},' \
      '"daily":{"time":["2026-11-06","2026-11-07"],"temperature_2m_max":[24.4,25.4],"temperature_2m_min":[17.0,15.6],"precipitation_sum":[3.4,1.5]}}')
    title, href, snippet = TinajaSearch.findings_clima(body, 'https://api.open-meteo.com/v1/forecast').first
    assert_equal 'El cielo de Mérida ahora: 22,0 °C, nublado', title
    assert_equal 'https://api.open-meteo.com/v1/forecast', href
    assert_includes snippet, 'de 17,0 °C a 24,4 °C, 3,4 mm de agua'
    assert_includes snippet, 'mañana: de 15,6 °C a 25,4 °C, 1,5 mm de agua'
  end

  def test_the_trade_recognizes_money_and_sky_and_leaves_the_rest
    assert_nil TinajaSearch.trade_of('¿quién eres y qué sabes hacer?')
    assert_equal :dolar, TinajaSearch.trade_of('¿precio del dólar hoy?')
    assert_equal :euro, TinajaSearch.trade_of('¿y el euro cuánto vale?')
    assert_equal :clima, TinajaSearch.trade_of('¿cómo está el clima en Mérida?')
    assert_equal :clima, TinajaSearch.trade_of('¿qué tiempo hace hoy?')
    # 'tiempo' without an actuality is not the sky: the bot keeps his own voice
    assert_nil TinajaSearch.trade_of('¿cuánto tiempo le dedicó al código?')
  end

  def test_results_reach_the_money_lamp_first
    called = []
    stub_dolar = '[' \
      '{"nombre":"Dólar","fuente":"oficial","promedio":896.1225,"fechaActualizacion":"2026-11-06T00:00:00-04:00"}]'
    TinajaSearch.stub(:get, lambda { |uri, _headers = {}|
      called << uri.to_s
      stub_dolar
    }) do
      findings = TinajaSearch.results('¿precio del dólar hoy?')
      assert_equal 1, findings.size
      assert_includes findings.first[0], '896,12'
    end
    assert_equal ['https://ve.dolarapi.com/v1/dolares'], called.uniq # no web search at all
  end

  def test_the_ladder_falls_straight_to_the_public_feeds
    calls = []
    TinajaSearch.stub(:get, lambda { |uri, _headers = {}| calls << uri.host.to_s }) do
      assert_nil TinajaSearch.results('¿quién ganó la FUTVE?') # every lamp out: no findings, no crash
    end
    # without a key and without the owner's SearXNG, the feeds carry the glance: Google first, Bing after
    assert_equal %w[news.google.com www.bing.com], calls
  end

  def test_the_first_feed_that_answers_carries_the_glance
    fixture = '<?xml version="1.0"?><rss><channel>' \
      '<item><title>Normal tiempo en Mérida</title><link>https://x.example/a</link>' \
      '<description>Chubasco por la tarde.</description></item>' \
      '<item><title></title><link>https://x.example/b</link><description>sin título</description></item>' \
      '</channel></rss>'
    TinajaSearch.stub(:get, lambda { |uri, _headers = {}|
      uri.to_s.include?('news.google.com') ? fixture : nil
    }) do
      findings = TinajaSearch.results('¿quién ganó la FUTVE?')
      assert_equal 1, findings.size # both the dead lamp and the untitled item stay out
      assert_equal ['Normal tiempo en Mérida', 'https://x.example/a', 'Chubasco por la tarde.'], findings.first
    end
  end

  def test_the_owner_own_lamp_leads_the_ladder
    ENV['TINAJA_SEARX_URL'] = 'http://127.0.0.1:8080'
    calls = []
    TinajaSearch.stub(:get, lambda { |uri, _headers = {}|
      calls << uri.host.to_s
      '{"results":[{"title":"Eco","url":"https://eco.example/1","content":"el circuito responde"}]}'
    }) do
      findings = TinajaSearch.results('¿quién ganó la FUTVE?')
      assert_equal 'Eco', findings.first[0]
      assert_equal 'el circuito responde', findings.first[2]
    end
    assert_equal %w[127.0.0.1], calls # the own answer closes the ladder; the feeds stay shut
  end
end
