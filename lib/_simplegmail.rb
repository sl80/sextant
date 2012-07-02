require 'rubygems'
require 'net/imap'
require 'tlsmail'
require 'time'

class SGmail
	def self.getenvelopes(*args, &block)
		@config = args[0]
		imap = Net::IMAP.new(@config[:server],@config[:port],true)
		imap.login(@config[:username], @config[:password])
		imap.select('INBOX')
		imap.search(["NOT", "DELETED"]).each do |message_id|
			#print imap.fetch(message_id, "RFC822")[0].attr['RFC822'].inspect
			#print imap.fetch(message_id, "ENVELOPE")[0].attr['ENVELOPE'].subject.inspect
			block.call(imap.fetch(message_id, "ENVELOPE")[0].attr['ENVELOPE'])
			#imap.store(message_id, "+FLAGS", [:Deleted])
		end
		imap.logout()
		imap.disconnect() 
	end
	
	def self.send(config, content, to)
		@config = config
		Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
		Net::SMTP.start('smtp.gmail.com', 587, 'gmail.com', @config[:fullusername], @config[:password], :login) do |smtp|
			smtp.send_message(content, @config[:fullusername], to)
		end
	end	
end

if __FILE__ == $0
config = {
	:server=>'imap.gmail.com', 
	:port=>'993', 
	:username=>'xxxxx', 
	:fullusername=>'xxx@googlemail.com', 
	:password=>'xxx'
}

content = <<-EOF
From: #{config[:fullusername]}
To: xxxxxx@gmail.com
MIME-Version: 1.0
Content-type: text/html
Subject: Hello!
Date: #{Time.now.rfc2822}

From: #{config[:fullusername]}
Neu:: How are you <a href="http://www.google.com">Google</a>.
EOF

SGmail.send(config, content, 'xxxxx@gmail.com')
SGmail.getenvelopes(config) do |e|
	print "#{e.subject}\r\n"
end
end