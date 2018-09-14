RSpec.describe Rack::Cloudflare do
  let!(:default_response) { Rack::Cloudflare::Middleware::AccessControl.blocked_response }

  before(:each) do
    Rack::Cloudflare::Headers.backup = true
    Rack::Cloudflare::Headers.original_remote_addr = 'ORIGINAL_REMOTE_ADDR'
    Rack::Cloudflare::Headers.original_forwarded_for = 'ORIGINAL_FORWARDED_FOR'

    Rack::Cloudflare::Middleware::AccessControl.blocked_message = 'Forbidden'
    Rack::Cloudflare::Middleware::AccessControl.blocked_response = default_response
  end

  it 'blocks access for non-Cloudflare networks' do
    env = { 'REMOTE_ADDR' => '127.0.0.1' }
    middleware = Rack::Cloudflare::Middleware::AccessControl.new(->(*) { 'success' })

    expect(middleware.call(env)).to eq([403, { 'Content-Type' => 'text/plain' }, ["Forbidden\n"]])
  end

  it 'grants access for Cloudflare networks' do
    env = { 'REMOTE_ADDR' => '103.21.244.1' }
    middleware = Rack::Cloudflare::Middleware::AccessControl.new(->(*) { 'success' })

    expect(middleware.call(env)).to eq('success')
  end

  it 'forbids access by default' do
    env = { 'REMOTE_ADDR' => '103.21.244.1' }
    middleware = default_response

    expect(middleware.call(env)).to eq([403, { 'Content-Type' => 'text/plain' }, ["Forbidden\n"]])
  end

  it 'forbids with custom message' do
    Rack::Cloudflare::Middleware::AccessControl.blocked_message = 'Go away'

    env = { 'REMOTE_ADDR' => '127.0.0.1' }
    middleware = Rack::Cloudflare::Middleware::AccessControl.new(->(_e) { 'success' })

    expect(middleware.call(env)).to eq([403, { 'Content-Type' => 'text/plain' }, ["Go away\n"]])
  end

  it 'forbids with custom response' do
    Rack::Cloudflare::Middleware::AccessControl.blocked_response = lambda do |_env|
      [301, { 'Location' => 'https://somewhere.else.xyz' }, ["Bye bye\n"]]
    end

    env = { 'REMOTE_ADDR' => '127.0.0.1' }
    middleware = Rack::Cloudflare::Middleware::AccessControl.new(->(_e) { 'success' })

    expect(middleware.call(env)).to eq([301, { 'Location' => 'https://somewhere.else.xyz' }, ["Bye bye\n"]])
  end

  it 'rewrites REMOTE_ADDR for trusted headers' do
    env = {
      'REMOTE_ADDR' => '103.21.244.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'ORIGINAL_FORWARDED_FOR' => nil,
      'ORIGINAL_REMOTE_ADDR' => '103.21.244.1',
      'REMOTE_ADDR' => '1.2.3.4',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    )
  end

  it "doesn't rewrite REMOTE_ADDR headers for untrusted headers" do
    env = {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4'
    )
  end

  it "doesn't rewrite HTTP_X_FORWARDED_FOR headers" do
    env = {
      'REMOTE_ADDR' => '103.21.244.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 0.0.0.0, 103.21.244.1'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'ORIGINAL_FORWARDED_FOR' => '1.2.3.4, 0.0.0.0, 103.21.244.1',
      'ORIGINAL_REMOTE_ADDR' => '103.21.244.1',
      'REMOTE_ADDR' => '1.2.3.4',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 0.0.0.0, 103.21.244.1'
    )
  end

  it 'backs up headers when trusted network' do
    env = {
      'REMOTE_ADDR' => '103.21.244.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'ORIGINAL_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1',
      'ORIGINAL_REMOTE_ADDR' => '103.21.244.1',
      'REMOTE_ADDR' => '1.2.3.4',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    )
  end

  it "doesn't back up headers when untrusted network" do
    env = {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    )
  end

  it "doesn't backup headers when backups disabled" do
    Rack::Cloudflare::Headers.backup = false

    env = {
      'REMOTE_ADDR' => '103.21.244.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'REMOTE_ADDR' => '1.2.3.4',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    )
  end

  it 'uses custom backup header names' do
    Rack::Cloudflare::Headers.original_remote_addr = 'BACKUP_REMOTE_ADDR'
    Rack::Cloudflare::Headers.original_forwarded_for = 'BACKUP_FORWARDED_FOR'

    env = {
      'REMOTE_ADDR' => '103.21.244.1',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    }
    middleware = Rack::Cloudflare::Middleware::RewriteHeaders.new(->(e) { e })

    expect(middleware.call(env)).to eq(
      'BACKUP_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1',
      'BACKUP_REMOTE_ADDR' => '103.21.244.1',
      'REMOTE_ADDR' => '1.2.3.4',
      'HTTP_CF_CONNECTING_IP' => '1.2.3.4',
      'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 103.21.244.1'
    )
  end
end