
# NewRelic instrumentation for ActiveRecord
if defined?(ActiveRecord) && defined?(ActiveRecord::Base) && !NewRelic::Control.instance['skip_ar_instrumentation']

  module NewRelic
    module Agent
      module Instrumentation
        module ActiveRecordInstrumentation
          
          def self.included(instrumented_class)
            instrumented_class.class_eval do
              alias_method :log_without_newrelic_instrumentation, :log
              alias_method :log, :log_with_newrelic_instrumentation
              protected :log
            end
          end
          
          def log_with_newrelic_instrumentation(sql, name, &block)
            
            return log_without_newrelic_instrumentation(sql, name, &block) unless NewRelic::Agent.is_execution_traced?
            
            # Capture db config if we are going to try to get the explain plans
            if (defined?(ActiveRecord::ConnectionAdapters::MysqlAdapter) && self.is_a?(ActiveRecord::ConnectionAdapters::MysqlAdapter)) ||
                (defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) && self.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter))
              supported_config = @config
            end
            if name && (parts = name.split " ") && parts.size == 2
              model = parts.first
              operation = parts.last.downcase
              metric_name = case operation
                            when 'load' then 'find'
                            when 'indexes', 'columns' then nil # fall back to DirectSQL
                            when 'destroy', 'find', 'save', 'create' then operation
                            when 'update' then 'save'
                            else
                              if model == 'Join'
                                operation
                              end
                            end
              metric = "ActiveRecord/#{model}/#{metric_name}" if metric_name
            end
            
            if metric.nil?
              metric = NewRelic::Agent::Instrumentation::MetricFrame.database_metric_name
              if metric.nil?
                if sql =~ /^(select|update|insert|delete|show)/i
                  # Could not determine the model/operation so let's find a better
                  # metric.  If it doesn't match the regex, it's probably a show
                  # command or some DDL which we'll ignore.
                  metric = "Database/SQL/#{$1.downcase}"
                else
                  metric = "Database/SQL/other"
                end
              end
            end
            
            if !metric
              log_without_newrelic_instrumentation(sql, name, &block)
            else
              metrics = [metric, "ActiveRecord/all"]
              metrics << "ActiveRecord/#{metric_name}" if metric_name
              self.class.trace_execution_scoped(metrics) do
                t0 = Time.now.to_f
                begin
                  log_without_newrelic_instrumentation(sql, name, &block) 
                ensure
                  NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, supported_config, Time.now.to_f - t0) 
                end
              end
            end
          end
          
        end
        
        # instrumentation to catch logged SQL statements in sampled transactions
        ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
          include ::NewRelic::Agent::Instrumentation::ActiveRecordInstrumentation
        end
        
        # This instrumentation will add an extra scope to the transaction traces
        # which will show the code surrounding the query, inside the model find_by_sql
        # method.
        ActiveRecord::Base.class_eval do
          class << self
            add_method_tracer :find_by_sql, 'ActiveRecord/#{self.name}/find_by_sql', :metric => false
          end
        end unless NewRelic::Control.instance['disable_activerecord_instrumentation']
      end
    end
  end
end
