module CLA
  class ProcessRunner
    class Notifier
      ANSI = {
        :reset          => 0,
        :black          => 30,
        :red            => 31,
        :green          => 32,
        :yellow         => 33,
        :blue           => 34,
        :magenta        => 35,
        :cyan           => 36,
        :white          => 37,
        :bright_black   => 30,
        :bright_red     => 31,
        :bright_green   => 32,
        :bright_yellow  => 33,
        :bright_blue    => 34,
        :bright_magenta => 35,
        :bright_cyan    => 36,
        :bright_white   => 37,
      }

      COLORS = [ :cyan, :yellow, :green, :magenta, :red, :blue, :bright_cyan, :bright_yellow,
                 :bright_green, :bright_magenta, :bright_red, :bright_blue ]

      def initialize(io)
        @out    = io
        @colors = {}
        @index  = -1
      end

      def started
        @out << "#{color(:bright_white)}                     runner | started#{color(:reset)}\n"

        self
      end

      def stopping
        @out << "#{color(:bright_white)}                     runner | stopping#{color(:reset)}\n"

        self
      end

      def signal_received(signal)
        @out << "#{color(:bright_white)}                     runner | received signal SIG#{signal}#{color(:reset)}\n"

        self
      end

      def child_unknown(pid)
        @out << "#{color(:bright_white)}                     runner | unknown child reaped (#{pid})#{color(:reset)}\n"

        self
      end

      def child_spawned(name, pid)
        @out << "#{color(:bright_white)}                     runner | spawning #{name} (#{pid})#{color(:reset)}\n"

        self
      end

      def child_interrupted(name, pid)
        @out << "#{color(:bright_white)}                     runner | stopping #{name} (#{pid}) with SIGINT#{color(:reset)}\n"

        self
      end

      def child_killed(name, pid)
        @out << "#{color(:bright_white)}                     runner | terminated #{name} (#{pid}) with SIGKILL#{color(:reset)}\n"

        self
      end

      def child_exited(name, pid, status)
        type, n = name.split('.')

        @out << "#{color(:bright_white)}                     runner | #{name} (#{pid}) exited with #{status}#{color(:reset)}\n"

        self
      end

      def child_output(name, pid, data)
        type, n       = name.split('.')
        first, *lines = data.chomp.lines.to_a

        output = "#{color(color_for(type))} %26s | %s" % [name, first]

        lines.each do |line|
          output << "                              " + line
        end

        output << "#{color(:reset)}\n"

        @out << output

        self
      end

      private

      def color_for(process)
        @colors[process] ||= COLORS[@index += 1 % COLORS.length]
      end

      def color(name)
        return "" unless @out.tty?
        return "" unless ansi = ANSI[name]
        "\e[#{ansi}m"
      end
    end

    class Process
      attr_reader :name, :out, :pid

      def initialize(notifier, name, handler)
        @notifier = notifier
        @name     = name
        @handler  = handler
      end

      def start
        @out, write = IO.pipe

        @pid = ::Process.fork do
          ['TERM', 'INT', 'QUIT', 'CHLD'].each do |signal|
            ::Signal.trap(signal, 'DEFAULT')
          end

          $0 += "[#{@name}]"

          $stdin.reopen('/dev/null')
          $stdout.reopen(write)
          $stderr.reopen(write)

          ObjectSpace.each_object(IO) do |io|
            next if [write, $stdin, $stdout, $stderr].include?(io)

            io.close unless io.closed?
          end

          write.write("\0")
          write.close
          @out.close unless @out.closed?

          @handler.call
        end

        write.close

        @notifier.child_spawned(@name, @pid)

        [@pid, @out]
      end

      def readable?
        @out && !@out.closed?
      end

      def to_io
        @out
      end

      def read_output
        buffer = ''

        loop do
          data = @out.read_nonblock(4096)
          buffer << data
          break if data.length < 4096
        end
      rescue ::IO::WaitReadable
      rescue ::EOFError
        @out.close
      ensure
        @notifier.child_output(@name, @pid, buffer) unless buffer.empty?
      end

      def reaped(status)
        read_output unless @out.closed?
        @notifier.child_exited(@name, @pid, status)
      end

      def interrupt
        ::Process.kill('INT', @pid)
        @notifier.child_interrupted(@name, @pid)

        self
      end

      def kill
        ::Process.kill('KILL', @pid)
        @notifier.child_killed(@name, @pid)

        self
      end
    end

    @@chars = {
      "\1" => 'TERM',
      "\2" => 'INT' ,
      "\3" => 'QUIT',
      "\4" => 'CHLD'
    }

    def initialize(name = $0, notifier = Notifier.new($stderr))
      @name      = name
      @notifier  = notifier
      @processes = {}
      @running   = {}
    end

    def process(name, instances = 1, handler = nil, &block)
      handler ||= block

      raise "process name cannot contain dots (#{name.inspect} given)"   if name.include?('.')
      raise "handler must be a callable that doesn't take any arguments" unless handler.respond_to?(:call) || handler.method(:call).arity != 0
      raise "process instances must be greater than 1" if instances < 1

      if instances > 1
        1.upto(instances) do |n|
          @processes["#{name}.#{n}"] = Process.new(@notifier, "#{name}.#{n}", handler)
        end
      else
        @processes[name] = Process.new(@notifier, name, handler)
      end

      self
    end

    def start
      $0 = "#{@name}"

      @signals, @queue = IO.pipe

      @@chars.each do |char, signal|
        ::Signal.trap(signal) do
          @queue.write(char)
        end
      end

      spawn(@processes.values)

      @notifier.started

      self
    end

    def join
      until readers.empty?
        reads, _ = IO.select(readers << @signals)

        signals_pending = false

        reads.each do |io|
          case io
          when @signals # don't process signals until later
            signals_pending = true
          else
            io.read_output
          end
        end

        if signals_pending
          read_nonblock(@signals).each_char do |char|
            signal = @@chars[char]

            @notifier.signal_received(signal)

            case signal
            when 'TERM', 'INT', 'QUIT'
              stop
            when 'CHLD'
              reap_children
            end
          end
        end
      end
    end

    def stop
      @stopped = true
      @notifier.stopping

      @running.each do |pid, process|
        process.interrupt
      end

      started = Time.now
      timeout = 5

      until @running.empty? || timeout <= 0 || IO.select([@signals], nil, nil, timeout).nil?
        read_nonblock(@signals)
        reap_children
        timeout = 5 - (Time.now - started)
      end

      @running.each do |pid, process|
        process.kill
      end

      until @running.empty?
        IO.select([@signals])
        read_nonblock(@signals)
        reap_children
      end

      @queue.close
      @signals.close
    end

    def stopped?
      @stopped
    end

    private

    def readers
      @running.values.select(&:readable?)
    end

    def spawn(processes)
      processes.map do |process|
        pid, pipe = process.start

        @running[pid]  = process

        pipe
      end.each do |pipe|
        pipe.read(1)
      end
    end

    def reap_children
      reaped = []

      until @running.empty?
        pid = ::Process.wait(0, ::Process::WNOHANG)

        break if pid.nil?

        status  = $?.to_i
        process = @running.delete(pid)

        if process.nil?
          @notifier.child_unknown(pid)
        else
          reaped << process unless stopped?
          process.reaped(status)
        end
      end
    ensure
      spawn(reaped)
    end

    def read_nonblock(io)
      buffer = ''

      loop do
        data = io.read_nonblock(4096)
        buffer << data
        break if data.length < 4096
      end
    rescue ::IO::WaitReadable
    ensure
      return buffer
    end
  end
end
