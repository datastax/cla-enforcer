require 'rubygems'
require 'bundler/setup'

require 'openssl'
require 'json'
require 'sinatra'
require 'sinatra/flash'
require 'sinatra/auth/github'
require 'sinatra/param'
require 'rack/parser'
require 'nori'
require 'nori/parser/nokogiri'

$: << File.expand_path('../', __FILE__)
$: << File.expand_path('../lib', __FILE__)

require 'cla'

post '/github/?' do
  content_type 'text/plain'
  request.body.rewind
  halt(403, "Invalud hub signature. Expected #{('sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha1'), ENV['GITHUB_VERIFIER_SECRET'], request.body.read))}, found #{request.env['HTTP_X_HUB_SIGNATURE']}...") unless request.env['HTTP_X_HUB_SIGNATURE'] == ('sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha1'), ENV['GITHUB_VERIFIER_SECRET'], request.body.read))
  halt(403, 'No payload found, halting...') unless params.include?('payload')

  begin
    payload = JSON.load(params['payload'])
  rescue => e
    CLA.logger.error("#{e.class.name}: #{e.message}\n    " + e.backtrace.join("\n    "))
    halt(406, 'Invalid JSON in payload')
  end

  if pull_request_opened?(payload)
    enqueue_command('github:pull_request', {
      user:   payload['repository']['owner']['login'],
      repo:   payload['repository']['name'],
      sender: payload['sender']['login'],
      number: payload['number']
    })

    status 202
    body   "Checking CLA status for #{payload['sender']['login']}..."
  elsif pull_request_commented?(payload)
    comment = payload['comment']['body']

    if /\[cla (\w+)\]/ =~ comment
      command = $1
      enqueue_command('github:command', {
        user:    payload['repository']['owner']['login'],
        repo:    payload['repository']['name'],
        sender:  payload['sender']['login'],
        number:  payload['issue']['number'],
        owner:   payload['issue']['user']['login'],
        command: command
      })

      status 202
      body   "Handling CLA command: #{command.inspect} for #{payload['sender']['login']}..."
    else
      status 200
      body   "Pull request comment skipped, no CLA action required"
    end
  else
    status 200
    body   "Unexpected event notification, no CLA action required"
  end
end

post '/docusign/?' do
  if envelope_status_update?(params)
    status = params['DocuSignEnvelopeInformation']['EnvelopeStatus']['RecipientStatuses']['RecipientStatus']['Status']

    enqueue_command('docusign:update', {
      envelope_id: params['DocuSignEnvelopeInformation']['EnvelopeStatus']['EnvelopeID'],
      status:      status,
      updated_at:  params['DocuSignEnvelopeInformation']['EnvelopeStatus']['RecipientStatuses']['RecipientStatus'][status] || Time.now
    })

    status 202
    body   "Processing envelope status update..."
  else
    status 200
    body   "Unexpected docusign connect notification, no action required"
  end
end

get '/' do
  erb :index, :layout => :layout
end

get '/form/?' do
  authenticate!

  redirect to('/status') if CLA.contributors.include?(github_user.login)

  @user    = github_user
  @param   = flash[:param]
  @message = flash[:message]

  erb :form, :layout => :layout
end

get '/status/?' do
  authenticate!

  @status  = CLA.contributors.find(github_user.login)
  @param   = flash[:param]
  @message = flash[:message]

  redirect to('/form') unless @status

  erb :status, :layout => :layout
end

post '/reset/?' do
  authenticate!

  envelope_id = CLA.contributors.delete(github_user.login)

  if envelope_id
    enqueue_command('docusign:void', envelope_id: envelope_id)
    redirect to('/form')
  else
    redirect to('/status'), param: 'form', message: 'Cannot reset completed CLA'
  end
end

post '/submit/?' do
  redirect to('/') unless github_user
  redirect to('/status') if CLA.contributors.include?(github_user.login)

  param :name,    String, max_length: 128, required: true
  param :email,   String, max_length: 254, required: true, format: EmailAddress
  param :company, String, max_length: 128, required: true

  CLA.contributors.insert(github_user.login, params['name'], params['email'], params['company'])

  enqueue_command('docusign:send', {
    login:   github_user.login,
    name:    params['name'],
    email:   params['email'],
    company: params['company']
  })

  @name  = params['name']
  @email = params['email']

  status 201
  erb :accepted
end

get '/authorize/?' do
  if params["error"]
    redirect to('/unauthenticated'), error: params["error"]
  else
    authenticate!
    redirect to(session.delete('return_to', '/'))
  end
end

get '/unauthenticated/?' do
  status       403
  content_type 'text/plain'

  if flash[:error]
    body "Unauthenticated: #{flash[:error]}"
  else
    body 'Unauthenticated'
  end
end

get '/ping/?' do
  status        200
  content_type 'text/plain'
  body         'Success!'
end

set :views, 'app/views'
set :public_folder, 'app/static'

set :sessions, key: 'cla.session', expire_after: 3600
set :session_secret, ENV['SINATRA_SECRET']

disable :show_exceptions, :raise_errors, :dump_errors

enable :raise_sinatra_param_exceptions

set :github_options, {
  :secret       => ENV['GITHUB_SECRET'],
  :client_id    => ENV['GITHUB_CLIENT_ID'],
  :callback_url => '/authorize'
}

register Sinatra::Auth::Github
helpers Sinatra::Param

use Rack::Parser, :parsers => {
  'text/xml' => proc { |data| Nori::Parser::Nokogiri.parse(data, {
      :strip_namespaces              => false,
      :delete_namespace_attributes   => false,
      :convert_tags_to               => nil,
      :convert_attributes_to         => nil,
      :advanced_typecasting          => true,
      :convert_dashes_to_underscores => true
    })
  },
}

helpers do
  def pull_request_opened?(payload)
    payload.has_key?('pull_request') && payload['action'] == 'opened'
  end

  def pull_request_commented?(payload)
    payload.has_key?('comment') &&
      payload.has_key?('issue') &&
      payload['issue'].has_key?('pull_request') &&
      payload['action'] == 'created'
  end

  def enqueue_command(command, data)
    CLA.queue.publish(command, JSON.dump(data))
  end

  def envelope_status_update?(params)
    params.has_key?('DocuSignEnvelopeInformation') &&
      params['DocuSignEnvelopeInformation'].has_key?('EnvelopeStatus') &&
      params['DocuSignEnvelopeInformation']['EnvelopeStatus'].has_key?('EnvelopeID') &&
      params['DocuSignEnvelopeInformation']['EnvelopeStatus'].has_key?('RecipientStatuses') &&
      params['DocuSignEnvelopeInformation']['EnvelopeStatus']['RecipientStatuses'].has_key?('RecipientStatus')
  end

  def redirect(uri, *args)
    if args.last.is_a?(::Hash)
      args.pop.each do |n, v|
        flash[n] = v
      end
    end

    super(uri, *args)
  end

  def label_color(status)
    case status
    when 'Sent'
      'warning'
    when 'Delivered'
      'info'
    when 'Completed'
      'success'
    when 'Declined'
      'danger'
    else
      'default'
    end
  end

  def agreement_name
    ENV['AGREEMENT_NAME'] || 'Contribution License Agreement'
  end
end

not_found do
  redirect to('/')
end

error Sinatra::Param::InvalidParameterError do |e|
  CLA.logger.info("Invalid parameter #{e.param} - #{e.message}")

  redirect to('/form'), param: e.param, message: e.message
end

error do |e|
  CLA.logger.error("#{e.class.name}: #{e.message}\n    " + e.backtrace.join("\n    "))

  status       500
  content_type 'text/plain'
  body         "#{e.class.name}: #{e.message}"
end

# Almost RFC2822 (No attribution reference available).
#
# This differs in that it does not allow local domains (test@localhost).
# 99% of the time you do not want to allow these email addresses
# in a public web application.
EmailAddress = begin
  if (RUBY_VERSION == '1.9.2' && RUBY_ENGINE == 'jruby' && JRUBY_VERSION <= '1.6.3') || RUBY_VERSION == '1.9.3'
    # There is an obscure bug in jruby 1.6 that prevents matching
    # on unicode properties here. Remove this logic branch once
    # a stable jruby release fixes this.
    #
    # http://jira.codehaus.org/browse/JRUBY-5622
    #
    # There is a similar bug in preview releases of 1.9.3
    #
    # http://redmine.ruby-lang.org/issues/5126
    letter = 'a-zA-Z'
  else
    letter = 'a-zA-Z\p{L}'  # Changed from RFC2822 to include unicode chars
  end
  digit          = '0-9'
  atext          = "[#{letter}#{digit}\!\#\$\%\&\'\*+\/\=\?\^\_\`\{\|\}\~\-]"
  dot_atom_text  = "#{atext}+([.]#{atext}*)+"
  dot_atom       = dot_atom_text
  no_ws_ctl      = '\x01-\x08\x11\x12\x14-\x1f\x7f'
  qtext          = "[^#{no_ws_ctl}\\x0d\\x22\\x5c]"  # Non-whitespace, non-control character except for \ and "
  text           = '[\x01-\x09\x11\x12\x14-\x7f]'
  quoted_pair    = "(\\x5c#{text})"
  qcontent       = "(?:#{qtext}|#{quoted_pair})"
  quoted_string  = "[\"]#{qcontent}+[\"]"
  atom           = "#{atext}+"
  word           = "(?:#{atom}|#{quoted_string})"
  obs_local_part = "#{word}([.]#{word})*"
  local_part     = "(?:#{dot_atom}|#{quoted_string}|#{obs_local_part})"
  dtext          = "[#{no_ws_ctl}\\x21-\\x5a\\x5e-\\x7e]"
  dcontent       = "(?:#{dtext}|#{quoted_pair})"
  domain_literal = "\\[#{dcontent}+\\]"
  obs_domain     = "#{atom}([.]#{atom})+"
  domain         = "(?:#{dot_atom}|#{domain_literal}|#{obs_domain})"
  addr_spec      = "#{local_part}\@#{domain}"
  pattern        = /\A#{addr_spec}\z/u
end
