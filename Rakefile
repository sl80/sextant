## Rakefile

require 'vendor/frozen.rb'
require 'sequel'
require 'sequel/extensions/migration'
require 'digest/sha1'

# Sequel.extension :migration
DB = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://database.db')
#current = Sequel::Migrator.get_current_migration_version(DB)

namespace(:db) do
desc "Migrate the database to the latest version"
	task :migrate do
		latest = Sequel::Migrator.apply(DB, 'migrations')
		#puts "Database successfully migrated to latest version (#{latest})." if current < latest
		puts "Migrations finished successfully."
	end
	task :reset do
		latest = Sequel::Migrator.apply(DB, 'migrations', 0)
		puts "Database resetted from (#{current}) to (#{latest})."
		puts "Migrations finished successfully."
	end
	task :down do
		latest = Sequel::Migrator.apply(DB, 'migrations', 1)
		puts "Database resetted from (#{current}) to (#{latest})."
		puts "Migrations finished successfully."
	end
end