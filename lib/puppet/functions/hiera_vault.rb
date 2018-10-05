#
# TODO:
#   - Figure out why this works with puppet apply and not puppet agent -t
#   - Look into caching values
#   - Test the options: default_field, default_field_behavior, and default_field_parse
#

Puppet::Functions.create_function(:hiera_vault) do
  begin
    require 'json'
  rescue LoadError
    raise Puppet::DataBinding::LookupError, "[hiera-vault] Must install json gem to use hiera-vault backend"
  end
  begin
    require 'vault'
  rescue LoadError
    raise Puppet::DataBinding::LookupError, "[hiera-vault] Must install vault gem to use hiera-vault backend"
  end
  begin
    require 'debouncer'
  rescue LoadError
    raise Puppet::DataBinding::LookupError, "[hiera-vault] Must install debouncer gem to use hiera-vault backend"
  end

  dispatch :lookup_key do
    param 'Variant[String, Numeric]', :key
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  @@shutdown = Debouncer.new(10) { Vault.shutdown }

  def lookup_key(key, options, context)
    split = key.split('::')
    return context.not_found if split.length < 2

    lookup_type = split.first
    key = split.last
    return context.not_found unless lookup_type =~ /vault_(list|key)/

    if strip_from_keys = options['strip_from_keys']
      raise ArgumentError, '[hiera-vault] strip_from_keys must be an array' unless strip_from_keys.is_a?(Array)

      strip_from_keys.each do |prefix|
        key = key.gsub(Regexp.new(prefix), '')
      end
    end

    if ENV['VAULT_TOKEN'] == 'IGNORE-VAULT'
      return context.not_found
    end

    vault_init(options, context)
    result = nil

    if lookup_type == 'vault_list'
      result = vault_list(key, options, context)
    end

    if lookup_type == 'vault_key'
      result = vault_get(key, options, context)
    end

    # Allow hiera to look beyond vault if the value is not found
    continue_if_not_found = options['continue_if_not_found'] || false

    if result.nil? and continue_if_not_found
      context.not_found
    else
      return result
    end
  end

  def vault_get(key, options, context)
    if ! ['string','json',nil].include?(options['default_field_parse'])
      raise ArgumentError, "[hiera-vault] invalid value for default_field_parse: '#{options['default_field_parse']}', should be one of 'string','json'"
    end

    if ! ['ignore','only',nil].include?(options['default_field_behavior'])
      raise ArgumentError, "[hiera-vault] invalid value for default_field_behavior: '#{options['default_field_behavior']}', should be one of 'ignore','only'"
    end

    answer = nil

    generic = options['mounts']['generic'].dup
    generic ||= [ '/secret' ]

    # Only generic mounts supported so far
    generic.each do |mount|
      path = File.join(mount, key)
      context.explain { "[hiera-vault] Looking in path #{path}" }

      begin
        puts "reading #{path}"
        secret = Vault.logical.read(path)
      rescue Vault::HTTPConnectionError
        context.explain { "[hiera-vault] Could not connect to read secret: #{path}" }
      rescue Vault::HTTPError => e
        context.explain { "[hiera-vault] Could not read secret #{path}: #{e.errors.join("\n").rstrip}" }
      end

      next if secret.nil?

      context.explain { "[hiera-vault] Read secret: #{key}" }

      if (options['default_field'] and ( ['ignore', nil].include?(options['default_field_behavior']) ||
         (secret.data.has_key?(options['default_field'].to_sym) && secret.data.length == 1) ) )

        return nil if ! secret.data.has_key?(options['default_field'].to_sym)

        new_answer = secret.data[options['default_field'].to_sym]

        if options['default_field_parse'] == 'json'
          begin
            new_answer = JSON.parse(new_answer, :quirks_mode => true)
          rescue JSON::ParserError => e
            context.explain { "[hiera-vault] Could not parse string as json: #{e}" }
          end
        end

      else
        # Turn secret's hash keys into strings allow for nested arrays and hashes
        # this enables support for create resources etc
        new_answer = secret.data.inject({}) { |h, (k, v)| h[k.to_s] = stringify_keys v; h }
      end

      if ! new_answer.nil?
        answer = new_answer
        break
      end
    end

    answer = context.not_found if answer.nil?
    @@shutdown.call
    return answer
  end

  def vault_list(key, options, context)
    list = nil
    generic = options['mounts']['generic'].dup
    generic ||= [ '/secret' ]

    # Only generic mounts supported so far
    generic.each do |mount|
      path = File.join(mount, key)
      list = Vault.logical.list(path)
    end
    list
  end

  def vault_init(options, context)
    begin
      Vault.configure do |config|
        config.address = options['address'] unless options['address'].nil?
        config.token = options['token'] unless options['token'].nil?
        config.ssl_pem_file = options['ssl_pem_file'] unless options['ssl_pem_file'].nil?
        config.ssl_verify = options['ssl_verify'] unless options['ssl_verify'].nil?
        config.ssl_ca_cert = options['ssl_ca_cert'] if config.respond_to? :ssl_ca_cert
        config.ssl_ca_path = options['ssl_ca_path'] if config.respond_to? :ssl_ca_path
        config.ssl_ciphers = options['ssl_ciphers'] if config.respond_to? :ssl_ciphers
      end

      if Vault.sys.seal_status.sealed?
        raise Puppet::DataBinding::LookupError, "[hiera-vault] vault is sealed"
      end

      context.explain { "[hiera-vault] Client configured to connect to #{Vault.address}" }
    rescue StandardError => e
      @@shutdown.call
      raise Puppet::DataBinding::LookupError, "[hiera-vault] Skipping backend. Configuration error: #{e}"
    end
  end

  # Stringify key:values so user sees expected results and nested objects
  def stringify_keys(value)
    case value
    when String
      value
    when Hash
      result = {}
      value.each_pair { |k, v| result[k.to_s] = stringify_keys v }
      result
    when Array
      value.map { |v| stringify_keys v }
    else
      value
    end
  end
end
