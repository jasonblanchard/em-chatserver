require 'rubygems' # or use Bundler.setup
require 'eventmachine'

class SimpleChatServer < EM::Connection

    @@connected_clients = []
    DM_REGEXP           = /^@([a-zA-Z0-9]+)\s*:?\s+(.+)/.freeze

    attr_reader :username

    def post_init
        @username = nil

        puts "A client has connected..."
        ask_username
    end
    
    def unbind
        @@connected_clients.delete(self)
        puts "[info] #{@username} has left..." if entered_username?
    end

    def receive_data(data)
        if entered_username?
            handle_chat_message(data.strip)
        else
            handle_username(data.strip)
        end
    end

    # Username handling
    def entered_username?
        !@username.nil? && !@username.empty?
    end

    def handle_username(input)
        if input.empty?
            send_line("Blank usernames are not allowed. Try again.")
            ask_username
        else
            @username = input
            @@connected_clients.push(self)
            self.other_peers.each { |c| c.send_data("#{@username} has joined the room\n") }
            puts "#{@username} has joined"

            self.send_line("[info] Ohai, #{@username}")
        end
    end

    def ask_username
        self.send_line("[info] Enter your Username:")
    end

    # Message handling
    def handle_chat_message(msg)
        if command?(msg)
            self.handle_command(msg)
        else
            if direct_message?(msg)
                self.handle_direct_message(msg)
            else
                self.announce(msg, "#{@username}")
            end
        end
    end

    def direct_message?(input)
        input =~ DM_REGEXP
    end

    def handle_direct_message(input)
        username, message = parse_direct_message(input)

        if connection = @@connected_clients.find { |c| c.username == username }
            puts "[dm] @#{@username} => @#{username}"
            connection.send_line("[dm] @#{@username}: #{message}")
        else
            send_line "#{@username} is not in the room. Here's who is: #{usernames.join(', ')}"
        end
    end

    def parse_direct_message(input)
        return [$1, $2] if input =~ DM_REGEXP
    end

    # Commands handling
    def command?(input)
        input =~ /exit|status$/i
    end

    def handle_command(cmd)
        case cmd
        when /exit$/i then self.close_connection
        when /status$/i then self.send_line("[chat server] It's #{Time.now.strftime('%H:%M')} and there are #{self.number_of_connected_clients} people in the room")
        end
    end


    # Helpers
    def announce(msg = nil, prefix= "[chat server]")
        @@connected_clients.each { |c| c.send_line("#{prefix}: #{msg}") } unless msg.empty?
    end
    def other_peers
        @@connected_clients.reject { |c| self == c }
    end

    def send_line(line)
        self.send_data("#{line}\n")
    end

    def number_of_connected_clients
        @@connected_clients.size
    end

    def usernames
        @@connected_clients.map { |c| c.username }
    end

end

# Note that this will block current thread.
EventMachine.run {
    Signal.trap("INT")  { EventMachine.stop }
    Signal.trap("TERM") { EventMachine.stop }
    
    EventMachine.start_server "127.0.0.1", 8081, SimpleChatServer
}
