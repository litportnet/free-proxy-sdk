Gem::Specification.new do |spec|
  spec.name = 'litportnet-free-proxy-sdk'
  spec.version = '0.1.1'
  spec.authors = ['Litport']
  spec.summary = 'Dependency-free Ruby client for Litport free-proxy snapshots.'
  spec.description = <<~RDOC
    == Litport Free Proxy SDK for Ruby

    Discover HTTP, SOCKS4 and SOCKS5 proxy records from Litport's public snapshot API.
    This Ruby 3.1+ client uses the standard library and requires no API key.

    == Features

    * Filter by country, protocol, anonymity and HTTPS support.
    * Set freshness, latency, uptime and minimum-check thresholds.
    * Retrieve normalized records or select the highest-ranked matching proxies.
    * Validate snapshot freshness and completeness, with configurable request timeouts.

    The client retrieves proxy records; your application controls how they are used.
    Free proxies are for testing only. Never send credentials, cookies or sensitive data through them.

    == Resources

    Browse the {free proxy list}[https://litport.net/free-proxy], read the
    {API documentation}[https://litport.net/docs/free-proxy-api], or see the
    {Ruby installation and usage examples}[https://github.com/litportnet/free-proxy-sdk/tree/main/packages/ruby].
  RDOC
  spec.homepage = 'https://litport.net/free-proxy'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'
  spec.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']
  spec.metadata = {
    'homepage_uri' => 'https://litport.net/free-proxy',
    'documentation_uri' => 'https://litport.net/docs/free-proxy-api',
    'source_code_uri' => 'https://github.com/litportnet/free-proxy-sdk',
    'bug_tracker_uri' => 'https://github.com/litportnet/free-proxy-sdk/issues'
  }
end
