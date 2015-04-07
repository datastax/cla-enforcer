module CLA
  class BackgroundWorker
    def initialize(logger, queue, github, docusign, contributors)
      @queue        = queue
      @logger       = logger
      @github       = github
      @docusign     = docusign
      @contributors = contributors
    end

    def run
      ["INT", "TERM", "QUIT"].each do |signal|
        ::Signal.trap(signal) do
          running = false
        end
      end

      socket  = @queue.subscribe
      running = true

      @logger.info("Worker started")

      while running
        @logger.info("Waiting for event")
        socket.recv_strings(parts = [])
        break if parts.empty?

        begin
          command, data = parts
          data = JSON.load(data)

          @logger.info("Received command #{command.inspect} with #{data.inspect}, processing")

          case command
          when 'github:pull_request'
            unless @contributors.signed?(data['sender']) || @github.collaborator?(data['user'], data['repo'], data['sender'])
              @github.request_signature(data['user'], data['repo'], data['number'], data['sender'])
            end
          when 'github:command'
            @logger.info("Unknown github command #{data['command'].inspect}, skipping")
          when 'docusign:send'
            envelope_id = @docusign.send_email(data['login'], data['name'], data['email'], data['company'])
            @contributors.update_envelope_id(data['login'], envelope_id)
          when 'docusign:update'
            @contributors.update_status(data['envelope_id'], data['status'], data['updated_at'])
          when 'docusign:void'
            @docusign.void_envelope(data['envelope_id'])
          else
            @logger.error("Unknown command #{command.inspect}, skipping")
          end
        rescue => e
          @logger.error("#{e.class.name}: #{e.message}\n    " + e.backtrace.join("\n    "))
        end
      end

      @logger.info("Worker stopped")
    end
  end
end
