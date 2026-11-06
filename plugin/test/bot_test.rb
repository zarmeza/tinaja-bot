# frozen_string_literal: true

require 'minitest/autorun'
require 'tinaja/testing'
require_relative '../bot'

class BotTest < Minitest::Test
  include Tinaja::Testing

  def test_hola_answers_a_courteous_greeting
    text = run_command(PLUGIN, 'hola').first
    assert_includes text, 'Un saludo, <@1>'
    assert_includes text, '¿En qué puedo servirle?'
  end

  def test_quien_presents_the_bot
    text = run_command(PLUGIN, 'quien').first
    assert_includes text, 'Mérida, Venezuela'
    assert_includes text, 'Andrés Bello'
    assert_includes text, 'ingeniero electrónico'
  end

  def test_mention_answers_courteously
    actions = run_event(PLUGIN, { 'type' => 'mention', 'message' => fake_message('<@42> hola', id: '5'), 'text' => 'hola' })
    assert_equal 1, actions.size
    assert_equal 'send', actions.first['type']
    assert_includes actions.first['content'], 'A la orden'
  end
end
