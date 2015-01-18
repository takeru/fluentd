require 'json'

module Fluent
  require 'fluent/config/error'

  module Config
    class Section < BasicObject
      def self.name
        'Fluent::Config::Section'
      end

      def initialize(params = {})
        @klass = 'Fluent::Config::Section'
        @params = params
      end

      def inspect
        "<Fluent::Config::Section #{@params.to_json}>"
      end

      def nil?
        false
      end

      def to_h
        @params
      end

      def +(other)
        Section.new(self.to_h.merge(other.to_h))
      end

      def instance_of?(mod)
        @klass == mod.name
      end

      def kind_of?(mod)
        @klass == mod.name || BasicObject == mod
      end
      alias is_a? kind_of?

      def [](key)
        @params[key.to_sym]
      end

      def respond_to_missing?(symbol, include_private)
        @params.has_key?(symbol)
      end

      def method_missing(name, *args)
        if @params.has_key?(name)
          @params[name]
        else
          super
        end
      end
    end

    module SectionGenerator
      def self.generate(proxy, conf, logger, stack = [])
        return nil if conf.nil?

        section_stack = ""
        unless stack.empty?
          section_stack = ", in section " + stack.join(" > ")
        end

        section_params = {}

        proxy.defaults.each_pair do |name, defval|
          varname = name.to_sym
          section_params[varname] = defval
        end

        if proxy.argument
          unless conf.arg.empty?
            key, block, opts = proxy.argument
            section_params[key] = self.instance_exec(conf.arg, opts, name, &block)
          end
          unless section_params.has_key?(proxy.argument.first)
            logger.error "config error in:\n#{conf}"
            raise ConfigError, "'<#{proxy.name} ARG>' section requires argument" + section_stack
          end
        end

        proxy.params.each_pair do |name, defval|
          varname = name.to_sym
          block, opts = defval
          if val = conf[name.to_s]
            section_params[varname] = self.instance_exec(val, opts, name, &block)
          end
          unless section_params.has_key?(varname)
            logger.error "config error in:\n#{conf}"
            raise ConfigError, "'#{name}' parameter is required" + section_stack
          end
        end

        proxy.sections.each do |name, subproxy|
          varname = subproxy.param_name.to_sym
          elements = (conf.respond_to?(:elements) ? conf.elements : []).select{ |e| e.name == subproxy.name.to_s }

          if subproxy.required? && elements.size < 1
            logger.error "config error in:\n#{conf}"
            raise ConfigError, "'<#{subproxy.name}>' sections are required" + section_stack
          end
          if subproxy.multi?
            section_params[varname] = elements.map{ |e| generate(subproxy, e, logger, stack + [subproxy.name]) }
          else
            if elements.size > 1
              logger.error "config error in:\n#{conf}"
              raise ConfigError, "'<#{subproxy.name}>' section cannot be written twice or more" + section_stack
            end
            section_params[varname] = generate(subproxy, elements.first, logger, stack + [subproxy.name])
          end
        end

        Section.new(section_params)
      end
    end
  end
end
