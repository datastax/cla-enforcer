require 'json'
require 'erb'
require 'logger'
require 'docusign_rest'
require 'sequel'
require 'octokit'
require 'pdfkit'
require 'tmpdir'

module CLA; extend self
  def worker
    @worker ||= begin
      BackgroundWorker.new(logger, queue, github, docusign, contributors)
    end
  end

  def runner
    @runner ||= begin
      ProcessRunner.new('cla-enforcer').tap do |run|
        run.process('http-server') { exec('puma', '-C', 'app/config/puma.rb') }
        run.process('worker')      { worker.run }
      end
    end
  end

  def queue
    @queue ||= begin
      DomainSocketQueue.new("messages.sock", logger)
    end
  end

  def logger
    @logger ||= begin
      logger           = Logger.new($stderr)
      logger.formatter = proc do |severity, datetime, progname, message|
        "[#{severity}] #{message}\n"
      end
      logger
    end
  end

  def docusign
    @docusign ||= DocusignClient.new(
      DocusignRest::Client.new,
      ENV['AGREEMENT_NAME'] || 'Contribution License Agreement',
      ENV['HOSTNAME']
    )
  end

  def contributors
    @contributors ||= PostgreSQLContributors.new(sequel[:contributors], github)
  end

  def github
    @github ||= begin
      GithubClient.new(
        Octokit::Client.new(
          access_token: ENV['GITHUB_ACCESS_TOKEN'],
          api_endpoint: ENV['GITHUB_API_ENDPOINT'] || 'https://api.github.com/'
        ),
        sequel[:tagged_pulls],
        sequel[:contributors],
        ENV['HOSTNAME'],
        ENV['GITHUB_HOSTNAME'] || 'https://github.com/',
        ENV['GITHUB_VERIFIER_SECRET'],
        ENV['CLA_LABEL_NAME'] || 'cla-missing',
        ENV['CLA_LABEL_COLOR'] || 'e11d21'
      )
    end
  end

  def sequel
    @sequel ||= begin
      db = Sequel.connect(ENV['DATABASE_URL'])
      db.loggers << logger
      db
    end
  end
end

module DocusignRest
  class Client
    def create_envelope_from_document(options={})
      ios = create_file_ios(options[:files])
      file_params = create_file_params(ios)

      post_body = {
        emailBlurb:   "#{options[:email][:body] if options[:email]}",
        emailSubject: "#{options[:email][:subject] if options[:email]}",
        documents: get_documents(ios),
        recipients: {
          signers: get_signers(options[:signers])
        },
        status: "#{options[:status]}",
        eventNotification: get_event_notification(options[:event_notification]),
        customFields: options[:custom_fields]
      }.to_json

      uri = build_uri("/accounts/#{acct_id}/envelopes")

      http = initialize_net_http_ssl(uri)

      request = initialize_net_http_multipart_post_request(
                  uri, post_body, file_params, headers(options[:headers])
                )

      response = http.request(request)
      JSON.parse(response.body)
    end

    def void_envelope(options = {})
      content_type = { 'Content-Type' => 'application/json' }
      content_type.merge(options[:headers]) if options[:headers]

      post_body = {
        "status" => "voided",
        "voidedReason" => options[:voided_reason] || "No reason provided."
      }.to_json

      uri = build_uri("/accounts/#{acct_id}/envelopes/#{options[:envelope_id]}")

      http = initialize_net_http_ssl(uri)
      request = Net::HTTP::Put.new(uri.request_uri, headers(content_type))
      request.body = post_body
      response = http.request(request)
      response
    end
  end
end

DocusignRest.configure do |config|
  config.endpoint       = ENV['DOCUSIGN_ENDPOINT'] || 'https://demo.docusign.net/restapi'
  config.username       = ENV['DOCUSIGN_USERNAME']
  config.password       = ENV['DOCUSIGN_PASSWORD']
  config.integrator_key = ENV['DOCUSIGN_INTEGRATOR_KEY']
  config.account_id     = ENV['DOCUSIGN_ACCOUNT_ID']
end

require 'cla/background_worker'
require 'cla/docusign_client'
require 'cla/github_client'
require 'cla/postgres_sql_contributors'
require 'cla/process_runner'
require 'cla/domain_socket_queue'
