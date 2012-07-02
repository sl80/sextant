# -*- coding: utf-8 -*-
require 'rubygems'
require 'vendor/frozen.rb'
require 'sequel'
require 'sequel/extensions/inflector'
require 'sinatra'
require 'scaffolding_extensions'
require 'yaml' 
require 'ya2yaml'
require 'jcode' if RUBY_VERSION < '1.9'
$KCODE = 'u'
require 'redcloth'
require 'iconv'

require "config" # mailkonfiguration etc.
CHECKMAIL = false

ENV['PSDOM'] = "piratensextant.de"
# ENV['PSDOM'] = "pp-sextant.heroku.com"


class MySinatraApp < Sinatra::Application
	
	configure do
		DB = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://database.db')
		set :sessions => true, :run => false
		set :show_exceptions, false if ENV['DATABASE_URL']
		ENV['APP_ROOT'] ||= File.dirname(__FILE__)
	    $:.unshift "#{ENV['APP_ROOT']}/vendor/plugins/newrelic_rpm/lib"
	    require 'newrelic_rpm'
	end

	Dir["lib/*.rb"].each{|x|load x}
	
	helpers do
		include Helpers
	end

	error do
		p1 = $!.inspect
		p2 = $!.backtrace.join("\n")
		p3 = request.inspect
		p4 = ENV.inspect
		adminmsg("#{p1}\n\n=== BACKTRACE:\n#{p2}\n\n=== REQUEST:\n#{p3}\n\n=== ENVIRONMENT:\n#{p4}")
		flash.clear
		erb :error500, :layout => false
	end

	not_found do
		flash.clear
		erb :error400
	end

	before do
		tz = request.cookies["TZ"]
		if !tz.nil?
			$tn = Time.now + 10*60*60 + tz.to_i*60
		else
			$tn = Time.now + 9*60*60
		end
		session[:user] = nil if logged_in? and !current_user
		if !logged_in? and 
		  request.path_info !~ /login/ and 
		  request.path_info !~ /xrds/ and 
		  request.path_info !~ /oid.*/ and 
		  request.path_info !~ /open.*/ and 
		  request.path_info !~ /images/ and 
		  request.path_info !~ /text/
			flash[:notice] = "Nicht angemeldet!"
			redirect '/text/index'
		end
		if logged_in? and current_user.nil?
			session[:user_id] = nil
			flash[:notice] = "Ungültiger Benutzer!"
			redirect '/'
		end
		if logged_in? and !current_user.is_qadmin and
		  request.path_info =~ /admin_/ 
			flash[:notice] = "Nur für Administratoren!"
			redirect '/text/index'
		end
			
#		if CHECKMAIL
#			ago = Time.now - State.first.lastmailupdate
#			if ago > 30
#				$stderr.puts("Checking mail ...")  	# mails checken
#				State.first.lastmailupdate = Time.now
#				State.first.save
#			end
#		end
	end

	get '/test500' do
		x = 1 / 0
		erb "Test für Fehler:500"
	end

	get '/adminlogin' do
		erb :adminlogin
	end
	
	get '/bear/:q' do
		@q = Questionaire[params[:q].to_i]
		return (erb "<h1>Datensatz nicht gefunden</h1>") if @q.nil?
		return (erb :error_acl) if !user_acl.split(",").include?(@q.scope)
		@o = Opinion.find_or_create(:user_id => session[:user_id], :questionaire_id => params[:q])
		erb :bear
	end

	get '/bear_adddel' do
		@q = Questionaire[params[:q]]
		return (erb "<h1>Nicht gefunden</h1>") if @q.nil?
		p = YAML.load(@q.topics_yml)
		line = p["themen"][params[:line].to_i]
		if / #\[\[.*\]\]#/.match(line)
			uid = line.strip.gsub(/.*#\[\[/, "").gsub(/\]\]#/, "").to_i
			return (erb "<h1>Bitte versuch es noch einmal.</h1>") if uid != current_user.id
			p["themen"].delete_at(params[:line].to_i)
			flash[:notice] = "Vorschlag gelöscht."
			@q.topics_yml = p.ya2yaml
			@q.save 
	  	end
		redirect "/bear/#{params[:q]}"
	end

	post '/bear_add' do
		@q = Questionaire[params[:q]]
		if !user_acl.split(",").include?(@q.scope)
			flash[:notice] = "Zugriff auf '#{@q.scope}' nicht erlaubt."
			redirect '/'
		end
		if current_user.is_qadmin or current_user.is_admin 
			flash[:notice] = "Stimme nicht unter deinem Admin-Login, sondern mit deiner OpenID ab."
			redirect '/'
		end
		if @q.phase.to_i != 1 
			flash[:notice] = "Ergänzungen nur in Phase I möglich."
			redirect '/'
		end
		p = YAML.load( @q.topics_yml )
		newitem = params["new"].gsub(/</, "&lt;").gsub(/>/, "&gt;")
		newitem ="#{newitem} #[[#{current_user.id}]]#"
		p["themen"].push(newitem)
		@q.topics_yml = p.ya2yaml
		@q.save 
		erb :bear
	end
	
	post '/bear_vote' do
		@q = Questionaire[params[:q]]
		if !user_acl.split(",").include?(@q.scope)
			flash[:notice] = "Zugriff auf '#{@q.scope}' nicht erlaubt."
			redirect '/'
		end
		if current_user.is_qadmin or current_user.is_admin 
			flash[:notice] = "Stimme bitte nicht unter deinem Admin-Login, sondern mit deiner OpenID ab."
			redirect '/'
		end
		if @q.phase.to_i != 2 
			flash[:notice] = "Abstimmungen nur in Phase II möglich."
			redirect '/'
		end
			
		@o = Opinion.find_or_create(:user_id => session[:user_id], :questionaire_id => params[:q])
		p = YAML.load( @q.topics_yml )
		pp = p["punkte"]
		v = []; sum = 0
		for i in 0..p["themen"].length-1
			v[i] = (params["t_#{i}".to_sym].nil? ? "" : CGI.escapeHTML(params["t_#{i}".to_sym]))
			v[i] = v[i].to_i
			v[i] = "" if v[i].to_i <= 0
			sum = sum + v[i].to_i # params["t_#{i}".to_sym].to_i
		end
		@o.opinion_arr = v.inspect
		if !p["approvot"].nil?
			erglink = p["verdeckt"].nil? ? " Weiter zum <a href='/synaprvot/#{params[:q]}'>Ergebnis</a>" : ""
			flash[:notice] = "Danke. Deine Meinung wurde gespeichert." + erglink
			@o.valid = true
		elsif sum == pp
			erglink = p["verdeckt"].nil? ? " Weiter zum <a href='/synopsis/#{params[:q]}'>Ergebnis</a>" : ""
			flash[:notice] = "Danke. Das #{pp==1 ? 'ist' : 'sind'} genau #{pp} Punkt#{pp==1 ? '' : 'e'}. Deine Meinung wurde als 'gültig' gespeichert." + erglink
			@o.valid = true
		else
			flash[:notice] = "Bitte verteile zusammen genau #{pp} Punkt#{pp==1 ? '' : 'e'} (derzeit #{sum}). Nur dann wird Deine Meinung als 'gültig' gespeichert."
			@o.valid = false
		end
		@o.save
		erb :bear
	end
	
#	post '/apply' do
#		email = params[:email]
#		hash = Digest::MD5.hexdigest(email.downcase)
#		u = User.find(:md5hash => hash)
#		if !u.nil?
#			User.sendmail(u.name, Digest::MD5.hexdigest(u.md5hash)[0..7], email)
#			# flash[:notice] = "Logindaten wurden versendet."
#			flash[:notice] = "Wenn die Validierung erfolgreich war, wurden die Logindaten versendet."
#		else
#			# flash[:notice] = "Unter dieser Mailadresse ist uns leider kein Pirat bekannt."
#			flash[:notice] = "Wenn die Validierung erfolgreich war, wurden die Logindaten versendet."
#		end
#		redirect '/text/index'
#	end

	post '/bear_del' do
		Opinion.find(:user_id => session[:user_id], :questionaire_id => params[:q]).destroy
		flash[:notice] = "Gelöscht."
		redirect '/'
	end
		
	get '/synaprvot/:q' do
		@q = Questionaire[params[:q]]
		return (erb "<h1>Datensatz nicht gefunden</h1>") if @q.nil?
		return (erb :error_acl) if !user_acl.split(",").include?(@q.scope)
		erb :synaprvot
	end

	get '/synopsis/:q' do
		@q = Questionaire[params[:q]]
		return (erb "<h1>Datensatz nicht gefunden</h1>") if @q.nil?
		return (erb :error_acl) if !user_acl.split(",").include?(@q.scope)
		erb :synopsis
	end

	get '/gvis/:q/:s' do
		@q = Questionaire[params[:q]]
		@s = params[:s]
		return (erb "<h1>Datensatz nicht gefunden</h1>") if @q.nil?
		return (erb :error_acl) if !user_acl.split(",").include?(@q.scope)
		erb :graphicsyn
	end
		
	get '/export/:q' do
		@q = Questionaire[params[:q]]
		return (erb "<h1>Datensatz nicht gefunden</h1>") if @q.nil?
		return (erb :error_acl) if !user_acl.split(",").include?(@q.scope)
		content_type "application/vnd.ms-excel; charset=ISO-8859-1" # utf-8
		attachment  "report.csv"
		Iconv.conv('ISO-8859-1', 'utf-8', (erb :export, :layout => false))

	end
	
	get '/xrds' do
		sitename = "localhost:4567"
 		sitename = ENV['PSDOM'] if ENV['DATABASE_URL'] 
		headers 'Content-Type' => "application/xrds+xml", 'X-XRDS-Location: ' => 'http://#{sitename}/xrds'
		<<-EOF
		<?xml version="1.0" encoding="UTF-8"?>
		<xrds:XRDS
			xmlns:xrds="xri://$xrds"
			xmlns:openid="http://openid.net/xmlns/1.0"
			xmlns="xri://$xrd*($v*2.0)">
			<XRD>
				<Service priority="1">
					<Type>http://specs.openid.net/auth/2.0/return_to</Type>
					<URI>http://#{sitename}/oidcomplete</URI>
				</Service>
			</XRD>
		</xrds:XRDS>
		EOF
	end

#	get '/wl_import' do
#		erb :wl_import
#	end
	
#	post '/wl_import' do
#		params[:hashlist].split("\n").each {|hash|
#			u = User.find_or_create(:md5hash => hash.strip)
#			u.name = "ppnds#{u.id}"
#			u.longname = "ppnds#{u.id}"
#			u.password = Digest::MD5.hexdigest(u.md5hash)[0..7]
#			u.is_admin = false
#			u.save
#			# $stderr.puts "+#{hash.strip}+"
#		}
#		flash[:notice] = "Whitelist importiert."
#		erb :app_index
#	end

#	get '/status' do
#		erb :status
#	end
	
# ======================================================
	get '/admin_profile' do
		@u = current_user
		if @u.is_qadmin and !@u.is_admin
			erb :admin_profile
		else
			flash[:notice]="Zugriff nicht erlaubt."
			redirect '/admin_index'
		end
	end
	
	post '/admin_profile_save' do
		@u = current_user
		if @u.is_qadmin and !@u.is_admin
			if params[:pw1] != ""
				if params[:pw1] != params[:pw2]
					flash[:notice]="Passwörter nicht gleich."
					redirect '/admin_profile'
				else
					@u.password = params[:pw1]
				end
			end
			@u.email = params[:email]
			@u.longname = params[:longname]
			@u.save
			flash[:notice]="Gespeichert."
			redirect '/admin_index'
		else
			flash[:notice]="Zugriff nicht erlaubt."
			redirect '/admin_index'
		end
	end

	get '/admin_index' do
		erb :admin_index
	end
	
	get '/admin_edit/:q' do
		@q = Questionaire[params[:q]]
		return (erb "<h1>Datensatz nicht gefunden</h1>") if @q.nil?
		erb :admin_edit
	end
	
	get '/admin_add' do
		@q = nil
		erb :admin_edit
	end

	get '/admin_del/:q' do
		return (erb "Neeee.") if !user_acl.split(",").include?(Questionaire[params[:q]].scope)
		Questionaire[params[:q]].destroy
		flash[:notice]="Gelöscht"
		redirect '/admin_index'
	end
	
	post '/admin_save' do
		scope = params[:scope]
		if user_acl.split(",").include?(scope)
			hsh = { :name => params[:name].gsub(/</, "&lt;").gsub(/>/, "&gt;"), 
					:phase => params[:phase].to_i,
					:topics_yml => params[:topics_yml].gsub(/</, "&lt;").gsub(/>/, "&gt;"),
					:scope => scope.gsub(/</, "&lt;").gsub(/>/, "&gt;")
				  } 
			if params[:q] == "" # add
				Questionaire.create(hsh)
				flash[:notice]="Angelegt"
			else
				Questionaire[params[:q].to_i].update(hsh)
				flash[:notice]="Gespeichert"
			end
		else
			flash[:notice]="Zugriff auf '#{scope}' nicht erlaubt."
		end
		redirect '/admin_index'
	end	

# ======================================================
	
	get '/' do
		erb :app_index
	end
	
	get '/text/:file' do
		fn = "./views/text/#{params[:file]}.txt"
		return (erb "<h1>Seite nicht gefunden.</h1>") if !File.exist?(fn)
		content = erb File.read(fn), :layout => false
		content = RedCloth.new(content).to_html
		erb content
	end
		
end

class Sequel::Model
	def self.scaffold_association_list_class; 'scaffold_associations_tree'; end
	def self.scaffold_convert_text_to_string; true; end 
	#def self.scaffold_association_list_class; 'recline'; end
	#def default_scaffold_methods; [:manage, :show, :destroy, :edit, :new, :search]; end
	def self.scaffold_associated_human_name(s)
		return case s
			when :user				then "Benutzer"
			when :users				then "Benutzer"
			when :pirate			then "Pirat"
			when :pirates			then "Piraten"
			when :questionaire		then "Meinungsbild"
			when :questionaires		then "Meinungsbilder"
			when :opinion			then "Meinung"
			when :opinions			then "Meinungen"
			else "SYM:#{s.to_s}"
		end 
	end
	def local_show_options; {}; end
end

class Scaf < Sinatra::Base
	include Helpers
	
	configure do
		set :sessions => true, :run => false
	end
	
	before do
		session[:user] = nil if logged_in? and !current_user
		if logged_in? and current_user.nil?
			session[:user_id] = nil
			flash[:notice] = "Ungültiger Benutzer!"
			redirect '/'
		end
		if !logged_in? or (logged_in? and !current_user.is_admin)
			flash[:notice] = "Nur für Systemadministratoren!"
			redirect '/text/index'
		end
	end
	
	@scaffold_template_dir = "#{File.dirname(__FILE__)}/views/scaffolds"
	
	ScaffoldingExtensions.javascript_library = 'JQuery'
	
	def scaffold_new_redirect(suffix, notice)
		flash[:notice]=notice
		redirect "/app/browse#{suffix}"
	end
	
	def scaffold_delete_redirect(suffix, notice)
		flash[:notice]=notice
		redirect "/app/browse#{suffix}"
	end
	
	def scaffold_new_orderposition_redirect(notice)
		flash[:notice]=notice
		redirect back
	end
	
    scaffold_all_models :only=>[User, Questionaire, Opinion, Post, State]
end

$myapp = Rack::Builder.app do
    map("/")	{run MySinatraApp}
#    map("/oidauth")	{run OpenIDAuth}
    map("/app")	{run Scaf}
end

if not ENV['DATABASE_URL']
	Rack::Handler.get('webrick').run($myapp, :Host=>'0.0.0.0', :Port=>4567) do |server|
	    trap(:INT){server.stop}
	end
end
