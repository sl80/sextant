# encoding: utf-8
require 'net/imap'
require 'tlsmail'
require 'time'

module Helpers

	def cc(c) # http://www.colorsontheweb.com/colorwizard.asp
		colors = 		[
			"#fff",	  # screen bg
			"#D8E1F4", # static
			"#D1DEFD", # dynamic
			"#FDE1D1", # flash
			"#FDE1D1", # motd
			"#C3D6EC", # help box
			"#eee" # main bg
		]
		#fp = File.open('colorconf.rb')
		#colors = fp.read
		#fp.close
		#eval(colors)[c]
		colors[c]
	end

	def user_acl			# Gibt die ACL des Users oder DEFAULT zurück
		acl = User[session[:user_id]].acl 
		# $stderr.puts("***** #{acl.inspect} ******") 
		(acl.nil? or (acl == "")) ? "L:NDS" : acl
	end
	
	def wouid(s)			# Von Option die UID abschneiden, wenn vorhanden
		if / #\[\[.*\]\]#/.match(s.to_s)
			return s.to_s.gsub(/ #\[\[.*\]\]#/, "")
		else
			return s.to_s
		end
	end
	
	def help(nr)			# erzeugt Hilfe-Button
		<<-EOF
		<img src='/images/info.png' alt='Hier klicken für Hilfe' 
			title='Hier klicken für Hilfe' onclick="javascript:toggleLayer('help#{nr}');"/>
		EOF
	end
		
	def helptext(nr)		# erzeugt Hilfetext
		hnr = ENV['DATABASE_URL'] ? "" : "   (H:#{nr})"
		content = erb File.read("./views/help/help#{nr}.txt"), :layout => false
		"<div style='padding:1.2em'>#{RedCloth.new(content + hnr).to_html}</div>"
	end

	def flash
		session[:flash] = {} if session[:flash] && session[:flash].class != Hash
		session[:flash] ||= {}
	end
	
	def cerb(*args)
		myerb = erb(*args)
		flash.clear
		myerb
	end

	def logged_in?
		session[:user_id]
	end
	
	def current_user
		User[session[:user_id]] if logged_in?
	end

	def partial(name, options={})
		erb("_#{name.to_s}".to_sym, options.merge(:layout => false))
	end
	
	def link_to(text, link='#', options = {})
		tag = "<a href='#{link}'"
		tag += " class=\"#{options[:class]}\"" if options[:class]
		tag += " target=\"#{options[:target]}\"" if options[:target]
		tag += " onclick=\"#{options[:onclick]}\"" if options[:onclick]
		tag += ">#{text}</a>"
	end
	
	def image_tag(file, options={})
		tag = "<img src='"
		tag += "/images/" unless file =~ /^http:\/\//
		tag += "#{file}'"
		tag += " class=\"#{options[:class]}\"" if options[:class]
		tag += " alt='#{options[:alt]}' title='#{options[:alt]}' " if options[:alt]
		tag += "/>"
	end
	
	# http://snippets.dzone.com/posts/show/7455 ## start
	
	def linkify( text )
#		@generic_URL_regexp = Regexp.new( '(^|[\n ])([\w]+?://[\w]+[^ \"\n\r\t<]*)', Regexp::MULTILINE | Regexp::IGNORECASE )
#		@starts_with_www_regexp = Regexp.new( '(^|[\n ])((www)\.[^ \"\t\n\r<]*)', Regexp::MULTILINE | Regexp::IGNORECASE )
#		@starts_with_ftp_regexp = Regexp.new( '(^|[\n ])((ftp)\.[^ \"\t\n\r<]*)', Regexp::MULTILINE | Regexp::IGNORECASE )
#		@email_regexp = Regexp.new( '(^|[\n ])([a-z0-9&\-_\.]+?)@([\w\-]+\.([\w\-\.]+\.)*[\w]+)', Regexp::IGNORECASE )		
		@generic_URL_regexp = Regexp.new( '(^|[\n\( ])([\w]+?://[\w]+[^ \"\n\r\t\)<]*)', Regexp::MULTILINE | Regexp::IGNORECASE )
		@starts_with_www_regexp = Regexp.new( '(^|[\n\( ])((www)\.[^ \"\t\n\r\)<]*)', Regexp::MULTILINE | Regexp::IGNORECASE )
		@starts_with_ftp_regexp = Regexp.new( '(^|[\n\( ])((ftp)\.[^ \"\t\n\r\)<]*)', Regexp::MULTILINE | Regexp::IGNORECASE )
		@email_regexp = Regexp.new( '(^|[\n\( ])([a-z0-9&\-_\.]+?)@([\w\-]+\.([\w\-\.]+\.)*[\w]+)', Regexp::IGNORECASE )
		s = text.to_s
		s.gsub!( @generic_URL_regexp, '\1<a href="\2" target="_blank">\2</a>' )
		s.gsub!( @starts_with_www_regexp, '\1<a href="http://\2" target="_blank">\2</a>' )
		s.gsub!( @starts_with_ftp_regexp, '\1<a href="ftp://\2" target="_blank">\2</a>' )
		s.gsub!( @email_regexp, '\1<a href="mailto:\2@\3" target="_blank">\2@\3</a>' )
		s
	end
	## end



	def fillgrid gtable, gfields, params
		@flds = gfields
		limit = params[:rows].to_i
		sidx = params[:sidx].nil? ? 'id' : params[:sidx]
		sord = params[:sord]
		@count = $DB["SELECT * FROM #{gtable}"].count
		@total_pages = @count > 0 ? (@count / limit).ceil+1 : 0
		@page = params[:page].to_i > @total_pages ? @total_pages : params[:page].to_i
		start = (limit*@page-limit) < 0 ? 0 : (limit*@page-limit)
		@dataset =  $DB["SELECT #{@flds.collect{|f|f.to_s}.join(',')} " +
						"FROM #{gtable} " +
						"ORDER BY #{sidx} " +
						"#{sord == 'asc' ? 'ASC' : 'DESC'} " +
						"LIMIT #{limit} OFFSET #{start}"
					]
		content_type 'application/xml', :charset => 'utf-8'
		erb :gridxml, :layout => false
	end
	
	def u2r(s)
		{"ä"=>"e4", "ö"=>"f6", "ü"=>"fc", 
		 "Ä"=>"c4", "Ö"=>"d6", "Ü"=>"dc", 
		 "ß"=>"df"
		}.each {|k, v| s.gsub!(k, "\\\\'#{v}")}; s
	end
	
	def u2h(s)
		s = s.gsub( 'ä', '&auml;' ).gsub( 'ö', '&ouml;' ).gsub( 'ü', '&uuml;' )
		s = s. gsub( 'Ä', '&Auml;' ).gsub( 'Ö', '&Ouml;' ).gsub( 'Ü', '&Uuml;')
		s.gsub( 'ß', '&szlig;' ).gsub( '<', '&lt;' ).gsub( '>', '&gt;' )
	end		

	def adminmsg(msg)
		#content = "From: PP-Sextant\nTo: pp.sextant@googlemail.com\nMIME-Version: 1.0\n"
		#content += "Content-type: text/plain\nSubject: PP-Sextant 500!\n"
		#content += "Date: #{Time.now.rfc2822}\n\n#{msg}\n"
		content = "From: PP-Sextant\nTo: #{$adminemail}\n"
		content += "Subject: Systemmeldung PP-Sextant 500!\n"
		content += "Date: #{Time.now.rfc2822}\n\n#{msg}\n"
		SGmail.send($gmailconfig, content, $adminemail)
	end	

end
