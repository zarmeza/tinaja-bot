# frozen_string_literal: true

# The day-lamp beside the jar: what the local engine doesn't know is asked of the web, whose
# findings lend an answer. Sources, in order of preference — every one of them was looked in
# the eye from the machine that runs the bot, and the day-lamps need no key:
#   1. By trade: dolarapi.com (Venezuelan dollar and euro) and Open-Meteo (the sky of Mérida) —
#      plain APIs meant for programs rather than browsers, the surest lamps for the common ask
#   2. Brave Search — only while TINAJA_BRAVE_API_KEY is set: the paid lamp outshines the rest
#   3. TINAJA_SEARX_URL — the owner's own SearXNG, for the day he raises one (a line in .env)
#   4. The feeds: Google News' RSS answers the day's ask first, Bing's RSS the rest of the web
#      after — feeds are meant to be read, so they don't fight back against programs the way
#      their search pages do
# Every lamp turns its answer into the same findings: an array of [title, href, snippet]. nil
# means the lamp is out — unreachable, unwilling, or simply not for that question — and the
# callers keep their own voice. Nothing here speaks to a channel.
require 'cgi'
require 'json'
require 'net/http'
require 'rexml/document'
require 'uri'

module TinajaSearch
  MAX_RESULTS = 5
  DOLAR_URL = 'https://ve.dolarapi.com/v1/dolares'
  EURO_URL = 'https://ve.dolarapi.com/v1/euros'
  CLIMA_URL = 'https://api.open-meteo.com/v1/forecast'
  # The sky the tinaja was born under; the stove answers of the weather of Mérida and can be
  # relocated to another corner with TINAJA_HOME_LAT / TINAJA_HOME_LON (see env.sample)
  HOME = { 'latitude' => ENV['TINAJA_HOME_LAT'] || '8.6047',
           'longitude' => ENV['TINAJA_HOME_LON'] || '-71.1476' }.freeze
  CLIMA_PARAMS = { 'current' => 'temperature_2m,precipitation,weather_code',
                   'daily' => 'temperature_2m_max,temperature_2m_min,precipitation_sum',
                   'forecast_days' => '2', 'timezone' => 'America/Caracas' }.freeze
  BRAVE_URL = 'https://api.search.brave.com/res/v1/web/search'
  BRAVE_PARAMS = { 'count' => MAX_RESULTS, 'search_lang' => 'es', 'country' => 've' }.freeze
  BING_URL = 'https://www.bing.com/search'
  GOOGLE_URL = 'https://news.google.com/rss/search'
  AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
  # The sky's own book, the WMO codes: the few the air of Mérida really wears
  WMO = { 0 => 'despejado', 1 => 'casi despejado', 2 => 'parcialmente nublado', 3 => 'nublado',
          45 => 'brumoso', 48 => 'bruma con escarcha', 51 => 'llovizna leve', 53 => 'llovizna',
          55 => 'llovizna intensa', 61 => 'lluvia leve', 63 => 'lluvia', 65 => 'lluvia intensa',
          66 => 'lluvia helada', 71 => 'nevada leve', 73 => 'nevada', 75 => 'nevada intensa',
          77 => 'granos de nieve', 80 => 'chubascos leves', 81 => 'chubascos',
          82 => 'chubascos violentos', 85 => 'nevadas de chubasco', 86 => 'nevadas fuertes',
          95 => 'tormenta eléctrica', 96 => 'tormenta con granizo', 99 => 'tormenta con granizo fuerte' }.freeze

  module_function

  # One glance at the web, whatever lamp answers first
  def results(query)
    by_trade(query) || feeds(query)
  end

  # ---- By trade: the common asks with their plain, sure lamps --------------------------------

  # When the ask is money or the sky, the trade lamps go ahead of any whole-web search: more
  # precise, no keys, and no search can compete with the source of the fact itself
  def by_trade(query)
    case trade_of(query)
    when :clima then clima_lamp
    when :dolar then money_lamp(DOLAR_URL, 'Dólar')
    when :euro then money_lamp(EURO_URL, 'Euro')
    end
  end

  def trade_of(query)
    ask = query.downcase.tr('áéíóú', 'aeiou')
    return :euro if /\beuro/.match?(ask)
    return :dolar if /\bdolar\b|\bmoneda|\bdivisa|\bbcv/.match?(ask)
    return :clima if /\bclima\b|\btemperat|\blluvia|\bllueve|\bllover|\bchubasco|\bhelada|\bneblina|\bmeteor/.match?(ask)
    return :clima if /\btiempo\b/.match?(ask) && /\b(hoy|manana|merida|venezuela)\b/.match?(ask)
  end

  def money_lamp(url, currency)
    uri = URI.parse(url)
    body = get(uri)
    return nil unless body

    findings_money(JSON.parse(body), url, currency)
  rescue StandardError
    nil
  end

  # The body of a money answer: one finding per rate (official's own first, the street's after)
  def findings_money(entries, url, currency)
    Array(entries).take(MAX_RESULTS).filter_map do |entry|
      price = entry['promedio']
      next unless price.is_a?(Numeric)

      date = (entry['fechaActualizacion'] || '')[0, 10]
      title = "#{currency} #{entry['fuente']} en Venezuela: #{money(price)}"
      [title, url, "Promedio al #{date}; fuente: #{entry['fuente']} (vía dolarapi.com)"]
    end
  end

  def clima_lamp
    uri = URI.parse(CLIMA_URL)
    uri.query = URI.encode_www_form(HOME.merge(CLIMA_PARAMS))
    body = get(uri)
    return nil unless body

    findings_clima(JSON.parse(body), uri.to_s)
  rescue StandardError
    nil
  end

  # The body of a sky answer: how it opens now, and how today and tomorrow promise to close
  def findings_clima(body, href)
    current = body.dig('current') || {}
    daily = body.dig('daily') || {}
    now = current['temperature_2m']
    code = WMO[current['weather_code']]
    return nil unless now && code

    title = "El cielo de Mérida ahora: #{degrees(now)}, #{code}"
    snippet = "Hoy: de #{degrees((daily['temperature_2m_min'] || [])[0])} a " \
              "#{degrees((daily['temperature_2m_max'] || [])[0])}, #{water((daily['precipitation_sum'] || [])[0])}"
    if (daily['time'] || []).size > 1
      snippet += "; mañana: de #{degrees((daily['temperature_2m_min'] || [])[1])} a " \
                 "#{degrees((daily['temperature_2m_max'] || [])[1])}, #{water((daily['precipitation_sum'] || [])[1])}"
    end
    snippet += ' (según Open-Meteo)'
    [[title, href, snippet]]
  end

  def degrees(value)
    return '?' unless value.is_a?(Numeric)

    sprintf('%.1f', value).tr('.', ',') + ' °C'
  end

  # The price of the money: Venezuelan speaking, with the thousands in their places
  def money(value)
    whole, decimals = sprintf('%.2f', value).split('.')
    whole = whole.reverse.gsub(/(\d{3})(?=\d)/, '\1.').reverse
    "#{whole},#{decimals} Bs"
  end

  def water(value)
    value.is_a?(Numeric) ? "#{sprintf('%.1f', value).tr('.', ',')} mm de agua" : 'sin agua de más'
  end

  # ---- Feeds and keys: the whole-web lamps ---------------------------------------------------

  # The feeds: Google News first — the community's asks are mostly of the day's world, where its
  # castellano ranking shines — and Bing after, the wider web for everything else
  def feeds(query)
    key = ENV['TINAJA_BRAVE_API_KEY']
    if key && !key.empty?
      findings = brave(query, key)
      return findings unless findings.nil? || findings.empty?
    end

    own = ENV['TINAJA_SEARX_URL']
    if own && !own.empty?
      findings = searx(own, query)
      return findings unless findings.nil? || findings.empty?
    end

    google(query) || bing(query)
  end

  def brave(query, key)
    uri = URI.parse(BRAVE_URL)
    uri.query = URI.encode_www_form(BRAVE_PARAMS.merge('q' => query))
    parse(get(uri, 'X-Subscription-Token' => key, 'Accept' => 'application/json'))
  rescue StandardError
    nil
  end

  # The Brave answer, already on the table: findings trimmed, untagged and titled, or the lamp out
  def parse(body)
    return nil unless body

    JSON.parse(body).dig('web', 'results').to_a.take(MAX_RESULTS).filter_map do |finding|
      title = strip(finding['title'].to_s)
      href = finding['url'].to_s
      [title, href, strip(finding['description'].to_s)] if !title.empty? && !href.empty?
    end
  rescue StandardError
    nil
  end

  def searx(own, query)
    uri = URI.parse(own)
    uri.query = URI.encode_www_form('q' => query, 'format' => 'json', 'language' => 'es')
    body = get(uri)
    return nil unless body

    JSON.parse(body).dig('results').to_a.take(MAX_RESULTS).filter_map do |finding|
      title = strip(finding['title'].to_s)
      href = finding['url'].to_s
      [title, href, strip(finding['content'].to_s)] if !title.empty? && !href.empty?
    end
  rescue StandardError
    nil
  end

  # The general web answer, and the day's-news answer after it: both as ready-made feeds
  def bing(query)
    uri = URI.parse(BING_URL)
    uri.query = URI.encode_www_form('q' => query, 'format' => 'rss')
    findings_rss(get(uri))
  end

  def google(query)
    uri = URI.parse(GOOGLE_URL)
    uri.query = URI.encode_www_form('q' => query, 'hl' => 'es-419', 'gl' => 'VE', 'ceid' => 'VE:es-419')
    findings_rss(get(uri))
  end

  def findings_rss(body)
    return nil unless body

    REXML::Document.new(body).elements.to_a('//item').take(MAX_RESULTS).filter_map do |item|
      title = strip(item.text('title') || '')
      href = item.text('link').to_s
      [title, href, strip(item.text('description') || '')] if !title.empty? && !href.empty?
    end
  rescue StandardError
    nil
  end

  def strip(fragment)
    CGI.unescapeHTML(fragment.gsub(/<[^>]*>/, '')).gsub(/\s+/, ' ').strip
  end

  # One GET, short fuses: a conversation must not wait on a slow lamp
  def get(uri, headers = {})
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = AGENT
    headers.each { |header, value| request[header] = value }
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5,
                               write_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    response.body.to_s.force_encoding(Encoding::UTF_8)
  end
end
