require 'launchy'
require 'quickbooks-ruby'
require 'uri'
require 'yaml'
require 'webrick'

$config = {}

begin
  $config = YAML.load_file(File.expand_path("~/.qbutil")) || {}
rescue Errno::ENOENT => e; end

if !$config['token'] || !$config['secret'] || !$config['realm_id']
  # Extract auth credentials
  server = WEBrick::HTTPServer.new(:Port => 0)
  port = server.config[:Port]
  server.mount_proc '/' do |req, res|
    $config.merge!(req.query)
    if $config['token'] && $config['secret'] && $config['realm_id']
      res.status = 200
      res.body = "Authorization successful. Please close this window."
    else
      res.status = 400
      res.body = "An error occurred! Unable to obtain OAuth credentials."
    end
    server.shutdown
  end
  thread = Thread.new do
    server.start
  end
  Launchy.open("http://quickbooks-auth-extractor.herokuapp.com/?send_to=http://localhost:#{port}")
  thread.join

  if $config['token'] && $config['secret'] && $config['realm_id']
    # WEBrick fills $config with weird WEBrick::HTTPUtils::FormData objects that
    # YAML can't properly marshal.
    $config.update($config) { |k, v| v.to_s }

    File.open(File.expand_path('~/.qbutil'), 'w') do |out|
      YAML.dump($config, out)
    end
  end
end

# Hack our Quickbooks API client

Quickbooks::Service::BaseService::BASE_DOMAIN.replace 'quickbooks-auth-proxy.herokuapp.com'

class ProxyConsumer < OAuth::Consumer
  # Initialize OAuth::Consumer with empty consumer credentials; our OAuth proxy
  # will sign the request.
  def initialize
    super(nil, nil)
  end

  # Disable request signing; this is performed by our proxy. All we need to do
  # is pass along our specific OAuth access token to the proxy via headers.
  def create_signed_request(http_method, path, token = nil, request_options = {}, *arguments)
    headers = arguments.last
    headers.merge!(token.to_proxy_headers)
    create_http_request(http_method, path, *arguments)
  end
end

class ProxyAccessToken < OAuth::AccessToken
  def initialize(token, secret)
    super(ProxyConsumer.new, token, secret)
  end

  def to_proxy_headers
    { 'oauth-token' => @token, 'oauth-token-secret' => @secret }
  end
end

def api_service(type)
  service = "Quickbooks::Service::#{type.to_s.camelcase}".constantize.new
  service.access_token = ProxyAccessToken.new($config['token'], $config['secret'])
  service.company_id = $config['realm_id']
  service
end
