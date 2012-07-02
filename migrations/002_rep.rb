class Base_002 < Sequel::Migration
    def up
        name = "admin"; password = "admin"
        salt = Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{name}--")
		crypted_password = Digest::SHA1.hexdigest("--#{salt}--#{password}--")
        DB[:users].insert(	:name => name, 
        					:longname => 'Admin', 
        					:password => '',
        					:active => true, 
        					:is_admin => true, 
        					:salt => salt, 
        					:crypted_password => crypted_password)
    end

    def down
    end
end