# = New Relic Agent
#
# New Relic RPM is a performance monitoring application for Ruby
# applications running in production.  For more information on RPM
# please visit http://www.newrelic.com.
#
# The New Relic Agent can be installed in Rails applications to gather
# runtime performance metrics, traces, and errors for display in a
# Developer Mode UI (mapped to /newrelic in your application server)
# or for monitoring and analysis at http://rpm.newrelic.com with just
# about any Ruby application.
#
# For detailed information on configuring or customizing the RPM Agent
# please visit our {support and documentation site}[http://support.newrelic.com].
#
# == Starting the Agent as a Gem
#
# For Rails, add:
#    config.gem 'newrelic_rpm'
# to your initialization sequence.
#
# For merb, do 
#    dependency 'newrelic_rpm'
# in the Merb config/init.rb
#
# For Sinatra, just require the +newrelic_rpm+ gem and it will
# automatically detect Sinatra and instrument all the handlers.
#
# For other frameworks, or to manage the agent manually, 
# invoke NewRelic::Agent#manual_start directly.
#
# == Configuring the Agent
# 
# All agent configuration is done in the <tt>newrelic.yml</tt> file.  This
# file is by default read from the +config+ directory of the
# application root and is subsequently searched for in the application
# root directory, and then in a <tt>~/.newrelic</tt> directory
#
# == Using with Rack/Metal
#
# To instrument middlewares, refer to the docs in 
# NewRelic::Agent::Instrumentation::Rack.
#
# == Agent API
#
# For details on the Agent API, refer to NewRelic::Agent.
# 
#
# :main: lib/new_relic/agent.rb
module NewRelic
  # == Agent APIs
  # This module contains the public API methods for the Agent.
  #
  # For adding custom instrumentation to method invocations, refer to 
  # the docs in the class NewRelic::Agent::MethodTracer.
  #
  # For information on how to customize the controller
  # instrumentation, or to instrument something other than Rails so
  # that high level dispatcher actions or background tasks show up as
  # first class operations in RPM, refer to
  # NewRelic::Agent::Instrumentation::ControllerInstrumentation and
  # NewRelic::Agent::Instrumentation::ControllerInstrumentation::ClassMethods.
  #
  # Methods in this module as well as documented methods in
  # NewRelic::Agent::MethodTracer and
  # NewRelic::Agent::Instrumentation::ControllerInstrumentation are
  # available to applications.  When the agent is not enabled the
  # method implementations are stubbed into no-ops to reduce overhead.
  #
  # Methods and classes in other parts of the agent are not guaranteed
  # to be available between releases.
  #
  # Refer to the online docs at support.newrelic.com to see how to
  # access the data collected by custom instrumentation, or e-mail
  # support at New Relic for help.
  module Agent
    extend self
    
    require 'new_relic/version'
    require 'new_relic/local_environment'
    require 'new_relic/stats'
    require 'new_relic/delayed_job_injection'
    require 'new_relic/metrics'
    require 'new_relic/metric_spec'
    require 'new_relic/metric_data'
    require 'new_relic/metric_parser'
    require 'new_relic/transaction_analysis'
    require 'new_relic/transaction_sample'
    require 'new_relic/noticed_error'
    require 'new_relic/histogram'
    
    require 'new_relic/agent/chained_call'
    require 'new_relic/agent/agent'
    require 'new_relic/agent/shim_agent'
    require 'new_relic/agent/method_tracer'
    require 'new_relic/agent/worker_loop'
    require 'new_relic/agent/stats_engine'
    require 'new_relic/agent/collection_helper'
    require 'new_relic/agent/transaction_sampler'
    require 'new_relic/agent/error_collector'
    require 'new_relic/agent/busy_calculator'
    require 'new_relic/agent/sampler'

    require 'new_relic/agent/instrumentation/controller_instrumentation'
    
    require 'new_relic/agent/samplers/cpu_sampler'
    require 'new_relic/agent/samplers/memory_sampler'
    require 'new_relic/agent/samplers/object_sampler'
    require 'new_relic/agent/samplers/delayed_job_lock_sampler'
    require 'set'
    require 'thread'
    require 'resolv'
    require 'timeout'
    
    # An exception that is thrown by the server if the agent license is invalid.
    class LicenseException < StandardError; end
    
    # An exception that forces an agent to stop reporting until its mongrel is restarted.
    class ForceDisconnectException < StandardError; end
      
    # An exception that forces an agent to restart.
    class ForceRestartException < StandardError; end
    
    # Used to blow out of a periodic task without logging a an error, such as for routine
    # failures.
    class IgnoreSilentlyException < StandardError; end
    
    # Used for when a transaction trace or error report has too much
    # data, so we reset the queue to clear the extra-large item
    class PostTooBigException < IgnoreSilentlyException; end
    
    # Reserved for future use.  Meant to represent a problem on the server side.
    class ServerError < StandardError; end

    class BackgroundLoadingError < StandardError; end
    
    @agent = nil

    # The singleton Agent instance.  Used internally.
    def agent #:nodoc:
      raise "Plugin not initialized!" if @agent.nil?
      @agent
    end
    
    def agent= new_instance #:nodoc:
      @agent = new_instance
    end
    
    alias instance agent #:nodoc:

    # Get or create a statistics gatherer that will aggregate numerical data
    # under a metric name.
    #
    # +metric_name+ should follow a slash separated path convention.  Application
    # specific metrics should begin with "Custom/".
    #
    # Return a NewRelic::Stats that accepts data
    # via calls to add_data_point(value).
    def get_stats(metric_name, use_scope=false)
      @agent.stats_engine.get_stats(metric_name, use_scope)
    end
    
    alias get_stats_no_scope get_stats 
    
    # Call this to manually start the Agent in situations where the Agent does
    # not auto-start.
    # 
    # When the app environment loads, so does the Agent. However, the Agent will
    # only connect to RPM if a web front-end is found. If you want to selectively monitor
    # ruby processes that don't use web plugins, then call this method in your
    # code and the Agent will fire up and start reporting to RPM.
    #
    # Options are passed in as overrides for values in the newrelic.yml, such
    # as app_name.  In addition, the option +log+ will take a logger that
    # will be used instead of the standard file logger.  The setting for
    # the newrelic.yml section to use (ie, RAILS_ENV) can be overridden
    # with an :env argument.
    #
    def manual_start(options={})
      raise unless Hash === options
      # Ignore all args but hash options
      options.merge! :agent_enabled => true 
      NewRelic::Control.instance.init_plugin options
    end
    
    # Shutdown the agent.  Call this before exiting.  Sends any queued data
    # and kills the background thread.
    def shutdown
      @agent.shutdown
    end        

    # Add instrumentation files to the agent.  The argument should be a glob
    # matching ruby scripts which will be executed at the time instrumentation 
    # is loaded.  Since instrumentation is not loaded when the agent is not
    # running it's better to use this method to register instrumentation than
    # just loading the files directly, although that probably also works. 
    def add_instrumentation file_pattern
      NewRelic::Control.instance.add_instrumentation file_pattern
    end

    # This method sets the block sent to this method as a sql obfuscator. 
    # The block will be called with a single String SQL statement to obfuscate.
    # The method must return the obfuscated String SQL. 
    # If chaining of obfuscators is required, use type = :before or :after
    #
    # type = :before, :replace, :after
    #
    # Example:
    #
    #    NewRelic::Agent.set_sql_obfuscator(:replace) do |sql|
    #       my_obfuscator(sql)
    #    end
    # 
    def set_sql_obfuscator(type = :replace, &block)
      agent.set_sql_obfuscator type, &block
    end
    
    
    # This method sets the state of sql recording in the transaction
    # sampler feature. Within the given block, no sql will be recorded
    #
    # usage:
    #
    #   NewRelic::Agent.disable_sql_recording do
    #     ...  
    #   end
    #     
    def disable_sql_recording
      state = agent.set_record_sql(false)
      begin
        yield
      ensure
        agent.set_record_sql(state)
      end
    end
    
    # This method disables the recording of transaction traces in the given
    # block.  See also #disable_all_tracing  
    def disable_transaction_tracing
      state = agent.set_record_tt(false)
      begin
        yield
      ensure
        agent.set_record_tt(state)
      end
    end
    
    # Cancel the collection of the current transaction in progress, if any.
    # Only affects the transaction started on this thread once it has started
    # and before it has completed.
    def abort_transaction!
      # The class may not be loaded if the agent is disabled
      if defined? NewRelic::Agent::Instrumentation::MetricFrame
        NewRelic::Agent::Instrumentation::MetricFrame.abort_transaction!
      end
    end
    
    # Yield to the block without collecting any metrics or traces in any of the
    # subsequent calls.  If executed recursively, will keep track of the first
    # entry point and turn on tracing again after leaving that block.
    # This uses the thread local +newrelic_untrace+
    def disable_all_tracing
      agent.push_trace_execution_flag(false)
      yield
    ensure
      agent.pop_trace_execution_flag
    end
    
    # Check to see if we are capturing metrics currently on this thread.
    def is_execution_traced?
      Thread.current[:newrelic_untraced].nil? || Thread.current[:newrelic_untraced].last != false      
    end

    # Set a filter to be applied to errors that RPM will track.
    # The block should evalute to the exception to track (which could be different from
    # the original exception) or nil to ignore this exception.
    #
    # The block is yielded to with the exception to filter. 
    # 
    # Do not call return.
    #
    def ignore_error_filter(&block)
      agent.error_collector.ignore_error_filter(&block)
    end
    
    # Record the given error in RPM.  It will be passed through the #ignore_error_filter
    # if there is one.
    # 
    # * <tt>exception</tt> is the exception which will be recorded
    # Options:
    # * <tt>:uri</tt> => The request path, minus any request params or query string.
    # * <tt>:referer</tt> => The URI of the referer
    # * <tt>:metric</tt> => The metric name associated with the transaction
    # * <tt>:request_params</tt> => Request parameters, already filtered if necessary
    # * <tt>:custom_params</tt> => Custom parameters
    #
    # Anything left over is treated as custom params
    #
    def notice_error(exception, options={})
      NewRelic::Agent::Instrumentation::MetricFrame.notice_error(exception, options)
    end

    # Add parameters to the current transaction trace on the call stack.
    #
    def add_custom_parameters(params)
      NewRelic::Agent::Instrumentation::MetricFrame.add_custom_parameters(params)
    end
    
    # The #add_request_parameters method is aliased to #add_custom_parameters
    # and is now deprecated.
    alias add_request_parameters add_custom_parameters #:nodoc:
    
    # Yield to a block that is run with a database metric name context.  This means
    # the Database instrumentation will use this for the metric name if it does not
    # otherwise know about a model.  This is re-entrant.
    #
    # * <tt>model</tt> is the DB model class
    # * <tt>method</tt> is the name of the finder method or other method to identify the operation with.
    #
    def with_database_metric_name(model, method, &block)
      if frame = NewRelic::Agent::Instrumentation::MetricFrame.current
        frame.with_database_metric_name(model, method, &block)
      else
        yield
      end
    end
  end 
end  
