#!/usr/bin/env ruby

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/strong-params'
require 'sinatra/flash'
require 'sinatra/activerecord'
require 'sinatra/reloader'

# Runtime dependencies
require 'sprockets'
require 'hamlit' # Sinatra does know to require HAML, but not Hamlit!

# Internal dependencies
require_relative 'models/user'
require_relative 'models/content_fragment'
require_relative 'models/toc'
require_relative 'models/file_attachment'
require_relative 'routes'

module SinatraApp 
  # Adapted from http://joeyates.info/2010/01/31/regular-expressions-in-sqlite/
  # Implements SQLite's REGEXP function in Ruby (like the commandline client's 'pcre' extension)
  class ActiveRecord::ConnectionAdapters::SQLite3Adapter
    def initialize(connection, logger, connection_options, config) # (db, logger, config)
      # Verbatim from https://github.com/rails/rails/blob/e2e63770f59ce4585944447ee237ec722761e77d/activerecord/lib/active_record/connection_adapters/sqlite3_adapter.rb
      super(connection, logger, config)
      @active     = nil
      @statements = StatementPool.new(self.class.type_cast_config_to_integer(config[:statement_limit]))
      configure_connection
      # Unchanged from source
      connection.create_function('regexp', 2) do |func, pattern, expression|
         regexp = Regexp.new(pattern.to_s, Regexp::IGNORECASE)
         if expression.to_s.match(regexp)
           func.result = 1
         else
           func.result = 0
         end
       end
    end
  end

  class Server < Sinatra::Base
    ###########################################################################
    # Configuration                                                           #
    ###########################################################################
    
    use Rack::Session::Cookie, secret: Config.session_secret
                              #, :key => 'rack.session',
                              #  :domain => 'localhost',
                              #  :path => '/',
                              #  :expire_after => 1.year.to_i

    # Load extensions.
    register Sinatra::ActiveRecordExtension
    register Sinatra::StrongParams
    register Sinatra::Flash

    # Things only needed for development, not production.
    configure :development do
      set :bind, Config.bind_address
      set :port, Config.bind_port
      enable :logging
      # http://recipes.sinatrarb.com/p/middleware/rack_commonlogger
      logfile = File.new(Config.root+"#{Config.environment}.log", 'w+')
      logfile.sync = true
      use Rack::CommonLogger, logfile
    end
    
    before do
      logger.datetime_format = "%H:%M:%S "
      logger.level = Logger::WARN
    end
    
    # Configure the application using user settings from config.rb.
    configure do
      # Stuff (I just wanted a comment here for good looks)
      set server: :puma
      set :environment, Config.environment
      set :root, Config.root
      set :views, Config.templates
      set :haml, {escape_html: false, format: :html5}
      set :bind, Config.bind_address
      set :port, Config.bind_port
      set :json_content_type, 'text/html' # Required by TinyMCE uploadfile plugin
      set :method_override, true # To be able to use RESTful methods
      set :public_folder, Config.static_files
      # Sprockets
      set :assets, Sprockets::Environment.new(root)
      assets.append_path Config.javascripts
      assets.append_path Config.stylesheets
      # Internationalisation
      # http://recipes.sinatrarb.com/p/development/i18n
      # A locale is only considered 'available' if the
      # corresponding file in locales/*.yml contains at
      # least one string!
      I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
      I18n.load_path = Dir[Config.translations+'*.yml']
      I18n.backend.load_translations
    end
    
    ###########################################################################
    # Helper Methods                                                          #
    ###########################################################################

    helpers do
      # Just some convenience (nicer to type current_user in views, etc.)
      def current_user
        (User.find(session[:user_id]) if session[:user_id]) || User.new
      end
      
      def view_mode
        if params[:view_mode]
          params[:view_mode].to_sym
        else
          :preview
        end
      end

      def locale
        I18n.locale
      end
      
      def content_class
        c = []
        if current_user && current_user.is_admin? && view_mode != :preview
          c << :editor
        else
          c << :user
        end
        c << :language_list if request.path_info.split('/').length < 2
        c.join(' ')
      end
    end
  end
end
