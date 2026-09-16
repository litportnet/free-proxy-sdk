Gem::Specification.new do |spec|
  spec.name = 'litportnet-free-proxy-sdk'
  spec.version = '0.1.0'
  spec.authors = ['Litport']
  spec.summary = 'Dependency-free Ruby client for Litport free-proxy snapshots.'
  spec.description = 'Fetch and locally filter Litport API snapshot records by freshness, latency, uptime, country, anonymity, and HTTPS support.'
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
