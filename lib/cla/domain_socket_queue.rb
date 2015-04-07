require 'socket'
require 'json'
require 'thread'

module CLA
  class DomainSocketQueue
    class DomainSocketServer
      def initialize(endpoint, logger)
        @endpoint = endpoint
        @logger   = logger
        @queue    = Queue.new

        sync = Mutex.new
        sync.lock
        @thread = Thread.new do
          Thread.abort_on_exception = true
          start_io(sync)
        end
        sync.unlock
        sync.lock
        sync.unlock
      end

      def recv_strings(parts = [])
        cmd, arg = @queue.pop
        case cmd
        when "data"
          parts.push(*arg)
        when "signal"
          ::Process.kill(arg, ::Process.pid)
          @thread.join
          @thread = nil
        end
      end

      private

      def start_io(sync)
        sync.lock
        stopped = false
        FileUtils.rm_f(@endpoint)
        server = UNIXServer.new(@endpoint)
        FileUtils.chmod(0777, @endpoint)
        @logger.info("Bound on #{@endpoint}")
        readers = []

        interrupt_r, interrupt_w = IO.pipe

        signal_codes     = {"\1" => 'TERM', "\2" => 'INT' , "\3" => 'QUIT'}
        default_handlers = {}
        signal_codes.each do |code, signal|
          default_handlers[signal] = ::Signal.trap(signal) do
            interrupt_w.write(code)
          end
        end
        sync.unlock

        until stopped
          reads, _ = IO.select(readers + [server, interrupt_r])
          reads.each do |sock|
            case sock
            when interrupt_r
              char = interrupt_r.read_nonblock(1)
              default_handlers.each do |signal, handler|
                ::Signal.trap(signal, handler)
              end
              stopped = true
              @queue.push(["signal", signal_codes[char]])
              break
            when server
              readers << server.accept
            else
              begin
                size = sock.read_nonblock(2).unpack('S!').first
                json = sock.read_nonblock(size).unpack('A*').first
                @queue.push(["data", JSON.load(json)])
              rescue ::IO::WaitReadable, ::EOFError
                readers.delete(sock)
                sock.close rescue nil
              end
            end
          end
        end
        @logger.info("IO thread stopped")
      rescue => e
        @logger.error("#{e.class.name}: #{e.message}\n" + Array(e.backtrace).join("\n"))
        raise e
      ensure
        server.close
        interrupt_r.close
        readers.each(&:close).clear
      end
    end

    class DomainSocketClient
      def initialize(endpoint, logger)
        @endpoint = endpoint
        @logger   = logger
      end

      def send_strings(parts)
        json  = JSON.dump(parts)
        size  = json.bytesize
        count = 0

        begin
          count += 1
          io.write([size, json].pack("S!A#{size}"))
        rescue ::IOError, ::Errno::EPIPE => e
          io.close rescue nil
          @io = nil
          if count < 10
            sleep(0.5)
            retry
          end
          @logger.error("#{e.class.name}: #{e.message}\n" + Array(e.backtrace).join("\n"))
          raise e
        rescue => e
          @logger.error("#{e.class.name}: #{e.message}\n" + Array(e.backtrace).join("\n"))
          raise e
        end
      end

      private

      def io
        @io ||= begin
          sock = UNIXSocket.new(@endpoint)
          @logger.info("Connected to #{@endpoint}")
          sock
        end
      end
    end

    def initialize(endpoint, logger)
      @endpoint = endpoint
      @logger   = logger
    end

    def publish(*parts)
      push_socket.send_strings(parts)
    end

    def subscribe
      DomainSocketServer.new(@endpoint, @logger)
    end

    private

    def push_socket
      @push_socket ||= DomainSocketClient.new(@endpoint, @logger)
    end
  end
end
