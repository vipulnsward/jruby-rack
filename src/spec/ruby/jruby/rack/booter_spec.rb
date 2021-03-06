#--
# Copyright (c) 2010-2012 Engine Yard, Inc.
# Copyright (c) 2007-2009 Sun Microsystems, Inc.
# This source code is available under the MIT license.
# See the file LICENSE.txt for details.
#++

require File.expand_path('spec_helper', File.dirname(__FILE__) + '/../..')
require 'jruby/rack/booter'

describe JRuby::Rack::Booter do
  
  let(:booter) do 
    JRuby::Rack::Booter.new JRuby::Rack.context = @rack_context
  end
  
  after(:all) { JRuby::Rack.context = nil }

  @@rack_env = ENV['RACK_ENV']
  
  after do
    @@rack_env.nil? ? ENV.delete('RACK_ENV') : ENV['RACK_ENV'] = @@rack_env
  end
  
  it "should determine the public html root from the 'public.root' init parameter" do
    @rack_context.should_receive(:getInitParameter).with("public.root").and_return "/blah"
    @rack_context.should_receive(:getRealPath).with("/blah").and_return "."
    booter.boot!
    booter.public_path.should == "."
  end

  it "should convert public.root to not have any trailing slashes" do
    @rack_context.should_receive(:getInitParameter).with("public.root").and_return "/blah/"
    @rack_context.should_receive(:getRealPath).with("/blah").and_return "/blah/blah"
    booter.boot!
    booter.public_path.should == "/blah/blah"
  end

  it "should default public root to '/'" do
    @rack_context.should_receive(:getRealPath).with("/").and_return "."
    booter.boot!
    booter.public_path.should == "."
  end

  it "should chomp trailing slashes from paths" do
    @rack_context.should_receive(:getRealPath).with("/").and_return "/hello/there/"
    booter.boot!
    booter.public_path.should == "/hello/there"
  end

  it "should determine the gem path from the gem.path init parameter" do
    @rack_context.should_receive(:getInitParameter).with("gem.path").and_return "/blah"
    @rack_context.should_receive(:getRealPath).with("/blah").and_return "."
    booter.boot!
    booter.gem_path.should == "."
  end

  it "should also be able to determine the gem path from the gem.home init parameter" do
    @rack_context.should_receive(:getInitParameter).with("gem.home").and_return "/blah"
    @rack_context.should_receive(:getRealPath).with("/blah").and_return "."
    booter.boot!
    booter.gem_path.should == "."
  end

  it "defaults gem path to '/WEB-INF/gems'" do
    @rack_context.should_receive(:getRealPath).with("/WEB-INF").and_return "."
    booter.boot!
    booter.gem_path.should == "./gems"
  end

  it "gets rack environment from rack.env" do
    ENV.delete('RACK_ENV')
    @rack_context.should_receive(:getInitParameter).with("rack.env").and_return "staging"
    booter.boot!
    booter.rack_env.should == 'staging'
  end
  
  it "gets rack environment from ENV" do
    ENV['RACK_ENV'] = 'production'
    @rack_context.stub!(:getInitParameter)
    booter.boot!
    booter.rack_env.should == 'production'
  end

  it "prepends gem_path to ENV['GEM_PATH']" do
    ENV['GEM_PATH'] = '/other/gems'
    @rack_context.should_receive(:getRealPath).with("/WEB-INF").and_return "/blah"
    booter.boot!
    ENV['GEM_PATH'].should == "/blah/gems#{File::PATH_SEPARATOR}/other/gems"
  end

  it "keeps ENV['GEM_PATH'] when gem_path is nil" do
    ENV['GEM_PATH'] = '/some/other/gems'
    booter.layout = layout = mock('layout')
    layout.stub!(:app_path).and_return '.'
    layout.stub!(:public_path).and_return nil
    layout.should_receive(:gem_path).and_return nil
    booter.boot!
    ENV['GEM_PATH'].should == "/some/other/gems"
  end  
  
  it "sets ENV['GEM_PATH'] to the value of gem_path if ENV['GEM_PATH'] is not present" do
    ENV['GEM_PATH'] = nil
    @rack_context.should_receive(:getRealPath).with("/WEB-INF").and_return "/blah"
    booter.boot!
    ENV['GEM_PATH'].should == "/blah/gems"
  end

  it "creates a logger that writes messages to the servlet context" do
    booter.boot!
    @rack_context.should_receive(:log).with(/hello/)
    booter.logger.info "hello"
  end
  
  before { $loaded_init_rb = nil }
  
  it "loads and executes ruby code in META-INF/init.rb if it exists" do
    @rack_context.should_receive(:getResource).with("/META-INF/init.rb").
      and_return java.net.URL.new("file:#{File.expand_path('init.rb', STUB_DIR)}")
    silence_warnings { booter.boot! }
    $loaded_init_rb.should == true
    defined?(::SOME_TOPLEVEL_CONSTANT).should == "constant"
  end

  it "loads and executes ruby code in WEB-INF/init.rb if it exists" do
    @rack_context.should_receive(:getResource).with("/WEB-INF/init.rb").
      and_return java.net.URL.new("file://#{File.expand_path('init.rb', STUB_DIR)}")
    silence_warnings { booter.boot! }
    $loaded_init_rb.should == true
  end

  it "delegates _path methods to layout" do
    booter.should_receive(:layout).at_least(:once).and_return layout = mock('layout')
    layout.should_receive(:app_path).and_return 'app/path'
    layout.should_receive(:gem_path).and_return 'gem/path'
    layout.should_receive(:public_path).and_return 'public/path'
    
    expect( booter.app_path ).to eq 'app/path'
    expect( booter.gem_path ).to eq 'gem/path'
    expect( booter.public_path ).to eq 'public/path'
  end

  it "changes working directory to app path on boot" do
    wd = Dir.pwd
    begin
      booter.stub!(:layout).and_return layout = mock('layout')
      layout.stub!(:app_path).and_return parent = File.expand_path('..')
      layout.stub!(:gem_path)
      layout.stub!(:public_path)

      booter.boot!
      expect( Dir.pwd ).to eq parent
    ensure
      Dir.chdir(wd)
    end
  end
  
  require 'jruby'
  
  if JRUBY_VERSION >= '1.7.0'
    it "adjusts load path when runtime.jruby_home == /tmp" do
      tmpdir = java.lang.System.getProperty('java.io.tmpdir')
      jruby_home = JRuby.runtime.instance_config.getJRubyHome
      load_path = $LOAD_PATH.dup
      begin # emulating a "bare" load path :
        $LOAD_PATH.clear
        $LOAD_PATH << "#{tmpdir}/lib/ruby/site_ruby"
        $LOAD_PATH << "#{tmpdir}/lib/ruby/shared"
        $LOAD_PATH << (JRuby.runtime.is1_9 ? "#{tmpdir}/lib/ruby/1.9" : "#{tmpdir}/lib/ruby/1.8")
        $LOAD_PATH << "." if RUBY_VERSION.index('1.8')
        # "stub" runtime.jruby_home :
        JRuby.runtime.instance_config.setJRubyHome(tmpdir)

        #booter.stub!(:require)
        booter.boot!

        expected = []
        if JRuby.runtime.is1_9
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/shared"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/1.9"
        else
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/shared"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/1.8"
          expected << "."
        end
        $LOAD_PATH.should == expected
      ensure # restore all runtime modifications :
        $LOAD_PATH.clear
        $LOAD_PATH.replace load_path
        JRuby.runtime.instance_config.setJRubyHome(jruby_home)
      end
    end
  else
    it "adjusts load path when runtime.jruby_home == /tmp" do
      tmpdir = java.lang.System.getProperty('java.io.tmpdir')
      jruby_home = JRuby.runtime.instance_config.getJRubyHome
      load_path = $LOAD_PATH.dup
      begin # emulating a "bare" load path :
        $LOAD_PATH.clear
        if JRuby.runtime.is1_9
          # a-realistic setup would be having those commented - but
          # to test the branched code there's artificial noise :
          $LOAD_PATH << "#{tmpdir}/lib/ruby/site_ruby/1.9"
          #$LOAD_PATH << "#{tmpdir}/lib/ruby/site_ruby/shared"
          $LOAD_PATH << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/shared"
          $LOAD_PATH << "#{tmpdir}/lib/ruby/site_ruby/1.8"
          #$LOAD_PATH << "#{tmpdir}/lib/ruby/1.9"
        else
          $LOAD_PATH << "#{tmpdir}/lib/ruby/site_ruby/1.8"
          #$LOAD_PATH << "#{tmpdir}/lib/ruby/site_ruby/shared"
          $LOAD_PATH << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/shared"
          #$LOAD_PATH << "#{tmpdir}/lib/ruby/1.8"
        end
        $LOAD_PATH << "."
        # "stub" runtime.jruby_home :
        JRuby.runtime.instance_config.setJRubyHome(tmpdir)

        booter.boot!

        expected = []
        if JRuby.runtime.is1_9
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/1.9"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/shared"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/1.8"
          #expected << "classpath:/META-INF/jruby.home/lib/ruby/1.9"
          expected << "."
          expected << "classpath:/META-INF/jruby.home/lib/ruby/1.9"
        else
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/1.8"
          expected << "classpath:/META-INF/jruby.home/lib/ruby/site_ruby/shared"
          #expected << "classpath:/META-INF/jruby.home/lib/ruby/1.8"
          expected << "."
          expected << "classpath:/META-INF/jruby.home/lib/ruby/1.8"
        end
        $LOAD_PATH.should == expected
      ensure # restore all runtime modifications :
        $LOAD_PATH.clear
        $LOAD_PATH.replace load_path
        JRuby.runtime.instance_config.setJRubyHome(jruby_home)
      end
    end
  end
  
  context "within a runtime" do
    
    describe "rack env" do
      
      before :each do
        # NOTE: this is obviously poor testing but it's easier to let the factory
        # setup the runtime for us than to hand copy/stub/mock all code involved
        servlet_context = javax.servlet.ServletContext.impl do |name, *args|
          case name.to_sym
            when :getRealPath then
              case args.first
                when '/WEB-INF' then File.expand_path('rack/WEB-INF', STUB_DIR)
              end
            when :getContextPath then
              '/'
            when :log then
              raise_logger.log(*args)
            else nil
          end
        end
        rack_config = org.jruby.rack.servlet.ServletRackConfig.new(servlet_context)
        rack_context = org.jruby.rack.servlet.DefaultServletRackContext.new(rack_config)
        app_factory = org.jruby.rack.DefaultRackApplicationFactory.new
        app_factory.init rack_context

        @runtime = app_factory.newRuntime
        @runtime.evalScriptlet("ENV.clear")
      end

      it "sets up (default) rack booter and boots" do
        # DefaultRackApplicationFactory#createApplicationObject
        @runtime.evalScriptlet("load 'jruby/rack/boot/rack.rb'")

        # booter got setup :
        should_not_eval_as_nil "defined?(JRuby::Rack.booter)"
        should_not_eval_as_nil "JRuby::Rack.booter"
        should_eval_as_eql_to "JRuby::Rack.booter.class.name", 'JRuby::Rack::Booter'

        # Booter.boot! run :
        should_not_eval_as_nil "ENV['RACK_ENV']"
        # rack got required :
        should_not_eval_as_nil "defined?(Rack::VERSION)"
        should_not_eval_as_nil "defined?(Rack.release)"
        # check if it got loaded correctly :
        should_not_eval_as_nil "Rack::Request.new({}) rescue nil"
      end
      
    end

    describe "rails env" do
      
      before :each do
        # NOTE: this is obviously poor testing but it's easier to let the factory
        # setup the runtime for us than to hand copy/stub/mock all code involved
        servlet_context = javax.servlet.ServletContext.impl do |name, *args|
          case name.to_sym
            when :getRealPath then
              case args.first
                when '/WEB-INF' then File.expand_path('rails30/WEB-INF', STUB_DIR)
              end
            when :getContextPath then
              '/'
            when :log then
              raise_logger.log(*args)
            else nil
          end
        end
        rack_config = org.jruby.rack.servlet.ServletRackConfig.new(servlet_context)
        rack_context = org.jruby.rack.servlet.DefaultServletRackContext.new(rack_config)
        app_factory = org.jruby.rack.rails.RailsRackApplicationFactory.new
        app_factory.init rack_context

        @runtime = app_factory.newRuntime
        @runtime.evalScriptlet("ENV.clear")
      end
      
      it "sets up rails booter and boots" do
        # RailsRackApplicationFactory#createApplicationObject
        @runtime.evalScriptlet("load 'jruby/rack/boot/rails.rb'")

        # booter got setup :
        should_not_eval_as_nil "defined?(JRuby::Rack.booter)"
        should_not_eval_as_nil "JRuby::Rack.booter"
        should_eval_as_eql_to "JRuby::Rack.booter.class.name", 'JRuby::Rack::RailsBooter'

        # Booter.boot! run :
        should_not_eval_as_nil "ENV['RACK_ENV']"
        should_not_eval_as_nil "ENV['RAILS_ENV']"
                
        # rack not yet required (let bundler decide which rack version to load) :
        should_eval_as_nil "defined?(Rack::VERSION)"
        should_eval_as_nil "defined?(Rack.release)"
      end
      
    end
    
  end
  
end
