class Base_001 < Sequel::Migration
    def up
        create_table(:users) do
			primary_key :id
			text 		:name
            String 		:md5hash
			text 		:longname
			text 		:password
			text 		:salt
			text 		:crypted_password
			text 		:email
			Boolean 	:is_admin
			Boolean 	:active
			timestamp 	:modified_at
        end
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
        
        create_table(:questionaires) do
			primary_key :id
			text 		:name
			Integer 	:phase
			text 		:topics_yml
			timestamp 	:modified_at
        end

=begin
--- 
themen: 
- Thema 1
- Thema 2
- Thema 3
- Thema 4
=end
        create_table(:opinions) do
			primary_key :id
			Integer		:questionaire_id
			Integer		:user_id
			text		:opinion_arr
			Boolean 	:valid
			timestamp 	:modified_at
        end
        
        create_table(:states) do
			primary_key :id
			timestamp 	:lastmailupdate
        end
        DB[:states].insert(:lastmailupdate => Time.now)

    end

    def down
        drop_table(:users)
        drop_table(:pirates)
        drop_table(:questionaires)
        drop_table(:opinions)
        drop_table(:states)
    end
end