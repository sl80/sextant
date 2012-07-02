module ScaffoldingExtensions
  class << self
    private
      # Ramaze's default location for models is model/
      def model_files
        @model_files ||= Dir["model/*.rb"]
      end
  end

  # Instance methods for Ramaze::Controller related necessary for Scaffolding Extensions
  module RamazeController
    private
      def scaffold_flash
        flash
      end

      def scaffold_method_not_allowed
        respond('Method not allowed', 405)
      end

      def scaffold_redirect_to(url)
        redirect(url)
      end

      # Renders user provided template if it exists, otherwise renders a scaffold template.
      # If a layout is specified (either in the controller or as an render_option), use that layout,
      # otherwise uses the scaffolded layout.  If :inline is one of the render_options,
      # use the contents of it as the template without the layout.
      def scaffold_render_template(action, options = {}, render_options = {})
        suffix = options[:suffix]
        suffix_action = "#{action}#{suffix}"
        @scaffold_options ||= options
        @scaffold_suffix ||= suffix
        @scaffold_class ||= @scaffold_options[:class]
        unless self.action.view
          if render_options.include?(:inline)
            response['Content-Type'] = 'text/javascript' if @scaffold_javascript
            render_options[:inline]
          else
            self.action.view = scaffold_path(action)
          end
        end
      end

      def scaffold_request_action
        action.name
      end

      def scaffold_request_env
        request.env
      end

      def scaffold_request_id
        request.params['id']
      end

      def scaffold_request_method
        request.env['REQUEST_METHOD']
      end

      def scaffold_request_param(v)
        request.params[v.to_s]
      end

      def scaffold_session
        session
      end

      # Treats the id option as special (appending it so the list of options),
      # which requires a lambda router.
      def scaffold_url(action, options = {})
        options[:id] ? r(action, options.delete(:id), options) : r(action, options)
      end
  end

  # Class methods for Ramaze::Controller related necessary for Scaffolding Extensions
  module MetaRamazeController
    DENY_LAYOUT_RE = %r{\A(scaffold_auto_complete_for|associations|add|remove)_}

    private
    # Denies the layout to names that match DENY_LAYOUT_RE (the Ajax methods).
    # Sets request.params['id'] if it was given as part of the request path.
    # Checks nonidempotent requests require POST.
    def scaffold_define_method(name, &block)
      scaffolded_methods.add(name)

      define_method(name) do |*args|
        scaffold_check_nonidempotent_requests
        request.params['id'] = args.shift if args.length > 0
        instance_eval(&block)
      end
    end

    # Adds a default scaffolded layout if none has been set.  Activates the Erubis
    # engine.  Includes the necessary scaffolding helper and controller methods.
    def scaffold_setup_helper
      map generate_mapping, :scaffolding_extensions
      map_views '/'
      map_layouts '/'
      engine :Erubis
      layout(:layout){|name, wish| DENY_LAYOUT_RE !~ name }

      o = Ramaze::App[:scaffolding_extensions].options
      o.roots = [scaffold_template_dir]
      o.views = ['/']
      o.layouts = ['/']

      include ScaffoldingExtensions::Controller
      include ScaffoldingExtensions::RamazeController
      include ScaffoldingExtensions::Helper
      include ScaffoldingExtensions::PrototypeHelper
    end
  end
end

# Add class methods necessary for Scaffolding Extensions
class Ramaze::Controller
  extend ScaffoldingExtensions::MetaController
  extend ScaffoldingExtensions::MetaRamazeController
end

