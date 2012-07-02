class Base_003 < Sequel::Migration
    def up
		alter_table :users do
            add_column :acl, String
            add_column :is_qadmin, :boolean
        end
		alter_table :questionaires do
            add_column :scope, String
        end
		alter_table :states do
            add_column :motd, :text
        end
        create_table(:posts) do
			primary_key :id
			text		:title
			text		:body
			timestamp 	:created_at
        end

    end

    def down
		alter_table :users do
            drop_column :acl
            drop_column :is_qadmin
        end
		alter_table :questionaires do
            drop_column :scope
        end
		alter_table :states do
            drop_column :motd
        end
        drop_table(:posts)
    end

end