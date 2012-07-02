require 'digest/sha1'
require 'digest/md5'
gem 'ruby-openid', '>=2.1.7'
require 'pathname'
require "openid"
require 'openid/extensions/sreg'
require 'openid/extensions/pape'
require 'openid/store/filesystem'

class User < Sequel::Model
	one_to_many :opinions
	@scaffold_browse_fields = [:id, :name, :longname, :is_admin, :is_qadmin, :acl]
	@scaffold_search_fields = [:name, :longname, :is_admin, :is_qadmin, :acl]
	
	def before_save
	    encrypt_password if self.password && self.password != ""
		self.password = nil
		self.modified_at = $tn
	end

	def authenticate?(password)
		Digest::SHA1.hexdigest("--#{self.salt}--#{password}--") == self.crypted_password
	end

	def encrypt_password
		self.salt = Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{self.name}--")
		self.crypted_password = Digest::SHA1.hexdigest("--#{self.salt}--#{password}--")
	end
	
#	def User.is_pirate(email)
#		hash = Digest::MD5.hexdigest(email.downcase)
#		return (!Pirate.find(:md5hash => hash).nil?)
#	end
	
#	def User.sendmail(login, password, email)
#		config = {
#			:server=>'imap.gmail.com', 
#			:port=>'993', 
#			:username=>'pp.sextant', 
#			:fullusername=>'pp.sextant@googlemail.com', 
#			:password=>'pp3sx45t'
#		}
#content = <<-EOF
#From: PP-Sextant
#To: #{email}
#MIME-Version: 1.0
#Content-type: text/html
#Subject: Zugangsdaten zum Piraten-Sextanten
#Date: #{Time.now.rfc2822}
#
#Ahoi, Mitpirat(in)!
#<br>
#<br>
#Deine Zugangsdaten zum Nieders&auml;chsischen <a href="http://pp-sextant.heroku.com">Piraten-#Sextanten</a> sind:<br>
#&nbsp;&nbsp;Login: #{login}<br>
#&nbsp;&nbsp;Passwort: #{password}<br>
#<br>
#Deine Meinung z&auml;hlt!
#
#EOF
#		SGmail.send(config, content, email)
#	end	
#
end

class MySinatraApp < Sinatra::Application
	get '/logout' do
		session[:user_id] = nil
		redirect '/text/index'
	end
	
	post '/login' do
		@name = params[:name]
		if user = User[:name => @name] and user.authenticate?(params[:password])
			session[:user_id] = user.id
			redirect '/'
		end
		flash[:error] = "Anmeldung fehlgeschlagen."
		redirect '/'
	end
	
	def openid_consumer
		storedir = ENV['DATABASE_URL'].nil? ? "/tmp" : ENV['HOME'].sub(/\/tmp\/home\/$/, '/tmp')
		@openid_consumer ||= OpenID::Consumer.new(session, OpenID::Store::Filesystem.new(storedir))  
		# ... OpenID::Store::Filesystem.new("#{File.dirname(__FILE__)}/tmp/openid"))  
	end

	def root_url
		request.url.match(/(^.*\/{2}[^\/]*)/)[1]
	end

#	get '/oidlogin' do    
#		erb :oid_login
#	end

	def oidsrv(op, nr=nil, s=nil)
		if not params["openid.identity"].nil?
			nr = case params["openid.identity"]
			when /openid.piratenpartei-niedersachsen.de/ 	: 0
			when /www.piratenpartei-hamburg.de/ 			: 1
			when /meinguter.name/ 							: 2
			end	
		end
		case op
		when :list
			["Niedersachsen", "Hamburg"] #, "MeinGuter.Name"]
		when :identifier
			case nr
			when 0: "http://openid.piratenpartei-niedersachsen.de/#{params[:openid_identifier]}"
			when 1: "http://www.piratenpartei-hamburg.de/users/#{params[:openid_identifier]}/openid"
#			when 2: "http://#{params[:openid_identifier]}.meinguter.name"
			end
		when :default
			["L:NDS", "L:HH", "TEST"][nr]		
		when :idurl	# nr unbekannt !		
			s
		when :idklar	# nr unbekannt !		
			case nr
			when 0: s.gsub(/^.*niedersachsen\.de\//,"")
			when 1:	s.gsub(/^http.*users\//, "").gsub(/\/openid$/, "")
			when 2: s.gsub(/http.*\:\/\//, "").gsub(/\.meinguter.name.*$/, "")
			else s
			end
		when :server
			nr
		end
	end

	post '/oidlogin' do
		oidlogin
	end
	
	get '/oidlogin/*/*' do   # http://localhost:4567/oidlogin?openid_server=1&openid_identifier=uwek
		a = params["splat"]
		params[:openid_server] = a[0]
		params[:openid_identifier] = a[1]
		oidlogin
	end
	
	def oidlogin
		msg = ""
		consumer = openid_consumer # OpenID::Consumer.new(session, store)
		begin
			if params[:openid_identifier].nil?
				flash[:notice] = "Bitte eine OpenID eingeben."
				redirect '/text/index'
				return
			end
			# identifier = "http://openid.piratenvorort.de/#{params[:openid_identifier]}"
			# identifier = "http://openid.piratenpartei-niedersachsen.de/#{params[:openid_identifier]}"
			identifier = oidsrv(:identifier, params[:openid_server].to_i)
			oidreq = consumer.begin(identifier)
		rescue OpenID::OpenIDError => e
			flash[:notice] = "Discovery failed for #{identifier}: #{e}"
			redirect '/text/index'
			return
		end
		sregreq = OpenID::SReg::Request.new
		sregreq.request_fields(['postcode'], false)
		# sregreq.request_fields(['dob', 'fullname'], false)
		oidreq.add_extension(sregreq)
		oidreq.return_to_args['did_sreg'] = 'y'
		#papereq = OpenID::PAPE::Request.new
		#papereq.add_policy_uri(OpenID::PAPE::AUTH_PHISHING_RESISTANT)
		#papereq.max_auth_age = 2*60*60
		#oidreq.add_extension(papereq)
		#oidreq.return_to_args['did_pape'] = 'y'
		# oidreq.return_to_args['force_post']='x'*2048
		if oidreq.send_redirect?(
			root_url, 
			root_url + "/oidcomplete", 
			params[:immediate])
			redirect oidreq.redirect_url(root_url, root_url + "/oidcomplete", params[:immediate])
		else
			oidreq.html_markup(root_url, 
				root_url + "/oidcomplete", params[:immediate], 
				{'id' => 'openid_form'})
		end
	end

	get '/oidcomplete' do
		msg = ""
		oidresp = openid_consumer.complete(params, request.url)
		status = oidresp.status
		
		# <Fieser Hack> !!! wg. nicht matchender Endpoints
		if status == OpenID::Consumer::FAILURE && 
			oidresp.message =~ /^No matching endpoint found after discovering/
			status = OpenID::Consumer::SUCCESS
			params[:did_pape] = false
			params[:did_sreg] = false
			hack = ".."
		else
			hack = ""
		end
		return (erb "Fehler. Bitte lies die FAQ, Frage 7.") if oidresp.display_identifier.nil?
		# </Fieser Hack>

		case status
		when OpenID::Consumer::FAILURE
			if oidresp.display_identifier
				msg += "Verifizierung für #{oidresp.display_identifier} fehlgeschlagen: #{oidresp.message}"
			else
				msg += "Verifizierung fehlgeschlagen: #{oidresp.message}"
			end
		when OpenID::Consumer::SUCCESS
			idurl = oidsrv(:idurl, nil, oidresp.display_identifier)
			idklar = oidsrv(:idklar, nil, oidresp.display_identifier)
			qurl = "http://#{ENV['PSDOM']}/oidlogin/#{oidsrv(:server, nil, oidresp.display_identifier)}/#{idklar}"
			msg += "Herzlich Willkommen. Mit dieser URL kannst du die Quick-Login-Funktion nutzen:<br><a href='#{qurl}'>#{qurl}</a> "
			#if params[:did_sreg]
			#	sreg_resp = OpenID::SReg::Response.from_success_response(oidresp, false)
			## $stderr.puts("####################\n#{sreg_resp.inspect}\n###################")
			#	sreg_message = "Simple Registration data was requested"
			#	if sreg_resp.empty?
			#		sreg_message << ", but none was returned."
			#	else
			#		sreg_message << ". The following data were sent:"
			#		sreg_resp.data.each {|k,v|
			#			sreg_message << "<br/><b>#{k}</b>: #{v}"
			#		}
			#	end
			#end
			if params[:did_pape]
				pape_resp = OpenID::PAPE::Response.from_success_response(oidresp)
				pape_message = "A phishing resistant authentication method was requested"
				if pape_resp.auth_policies.member? OpenID::PAPE::AUTH_PHISHING_RESISTANT
					pape_message << ", and the server reported one."
				else
					pape_message << ", but the server did not report one."
				end
				if pape_resp.auth_time
					pape_message << "<br><b>Authentication time:</b> #{pape_resp.auth_time} seconds"
				end
				if pape_resp.nist_auth_level
					pape_message << "<br><b>NIST Auth Level:</b> #{pape_resp.nist_auth_level}"
				end
			end
			# oid = oidresp.display_identifier.gsub(/^.*\//, "")
			u = User.find_or_create(:name => Digest::MD5.hexdigest(idurl), :longname => "Pirat", :is_admin => false)
			sreg_message = "Deine Mitgliedsbereiche: Nicht übertragen."
			if params[:did_sreg]
				sreg_resp = OpenID::SReg::Response.from_success_response(oidresp, false)
				if !sreg_resp.empty?
					acl = sreg_resp.data["postcode"]
					if !acl.nil? and acl != ""
						u.acl = acl
					else
						u.acl = oidsrv(:default)
					end
				else	
					u.acl = oidsrv(:default)
				end
				sreg_message = "Deine Mitgliedsbereiche: #{acl}"
				u.save
			end
			session[:user_id] = u.id 
			flash[:notice] = "#{msg}#{hack}"
			#flash[:notice] = "#{msg}<br>#{sreg_message}<br>#{pape_message}"
			# redirect '/'
			erb :app_index
			#return
		when OpenID::Consumer::SETUP_NEEDED
			msg += "Immediate request failed - Setup Needed"
		when OpenID::Consumer::CANCEL
			msg += "OpenID transaction cancelled."
		else
		end
		flash[:notice] = "#{msg}"
		# redirect '/text/index'
		erb RedCloth.new(erb File.read("./views/text/index.txt"), :layout => false).to_html
	end

end