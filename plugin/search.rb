# frozen_string_literal: true

# The day-lamp beside the jar: what the local engine doesn't know is asked of the web, whose
# findings lend an answer. The lamp is Brave Search under its own key — stable JSON, no scraping
# against the wind, the key living only in the environment (see env.sample):
#   TINAJA_BRAVE_API_KEY   required for the lamp to light (free tier: 2000 looks a month)
# With the key absent the lamp stays dark and the callers keep their own voice; nothing here
# speaks to a channel.
require 'cgi'
require 'json'
require 'net/http'
require 'uri'

module TinajaSearch
  ENDPOINT = 'https://api.search.brave.com/res/v1/web/search'
  MAX_RESULTS = 5
  PARAMS = { 'count' => MAX_RESULTS, 'search_lang' => 'es', 'country' => 've' }.freeze

  module_function

  def results(query)
    key = ENV['TINAJA_BRAVE_API_KEY']
    return nil unless key && !key.empty?

    body = fetch(query, key)
    return nil unless body

    parse(body)
  rescue StandardError
    nil
  end

  # One lamp lighting: GET with the token in the header, short fuses — a conversation must not
  # wait on a slow lamp
  def fetch(query, key)
    uri = URI.parse(ENDPOINT)
    uri.query = URI.encode_www_form(PARAMS.merge('q' => query))
    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/json'
    request['X-Subscription-Token'] = key
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5,
                               write_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).to_s.force_encoding(Encoding::UTF_8)
  end

  # The body of a lit lamp, already on the table: [title, href, snippet], trimmed and untagged.
  # An answer without web findings still lights: [] — the callers confess, they don't invent
  def parse(body)
    found = JSON.parse(body).dig('web', 'results') || []
    found.take(MAX_RESULTS).filter_map do |finding|
      title = strip(finding['title'].to_s)
      href = finding['url'].to_s
      [title, href, strip(finding['description'].to_s)] if title && !title.empty? && !href.empty?
    end
  end

  def strip(fragment)
    CGI.unescapeHTML(fragment.gsub(/<[^>]*>/, '')).gsub(/\s+/, ' ').strip
  end
end
