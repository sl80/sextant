class Questionaire < Sequel::Model
	one_to_many :opinions
	@scaffold_column_types = {:topics_yml => :text} 
	@scaffold_column_options_hash = {:topics_yml => {:cols=>'55', :rows=>'10'}} 
	@scaffold_browse_fields = [:name, :phase, :scope] 

	def before_destroy
		self.opinions.each {|o| o.destroy }
	end
end

class Opinion < Sequel::Model
	many_to_one :user
	many_to_one :questionaire
	@scaffold_browse_fields = [:id, :questionaire, :user, :valid]
	
	def before_save
		if !self.valid.nil?
			self.modified_at = $tn
		end
	end
end

class State < Sequel::Model
	@scaffold_column_types = {:motd => :text} 
	@scaffold_column_options_hash = {:motd => {:cols=>'50', :rows=>'10'}} 
end

class Post < Sequel::Model
	@scaffold_column_types = {:body => :text} 
	@scaffold_column_options_hash = {:body => {:cols=>'50', :rows=>'10'}} 
	@scaffold_browse_fields = [:title, :created_at]
	def before_save
		self.created_at = Time.now
	end

end
