module Octopress
  module Plugins
    @plugins = []
    @local_plugins = []

    def self.theme
      @theme
    end

    def self.plugin(name)
      if name == 'theme'
        @theme
      else
        @plugins.concat(@local_plugins).each do |p|
          return p if p.name == name
        end
      end
    end

    def self.plugins
      [@theme].concat(@plugins).concat(@local_plugins).compact
    end

    def self.embed(name, file, site)
      plugin(name).embed(file, site)
    end

    def self.register_plugin(plugin, name, type='plugin')
      new_plugin = plugin.new(name, type)

      if type == 'theme'
        @theme = new_plugin
      elsif type == 'local_plugin'
        @plugins << new_plugin
      else
        @local_plugins << new_plugin
      end
    end

    def self.register_layouts(site)
      plugins.each do |p|
        p.layouts.clone.each { |layout| layout.register(site) }
      end
    end

    def self.custom_dir(site)
      site.config['custom'] || CUSTOM_DIR
    end

    def self.fingerprint(paths)
      paths = [paths] unless paths.is_a? Array
      Digest::MD5.hexdigest(paths.clone.map! { |path| "#{File.mtime(path).to_i}" }.join)
    end
    
    def self.combined_stylesheet_path(media)
      File.join('stylesheets', "site-#{media}-#{@combined_stylesheets[media][:fingerprint]}.css")
    end

    def self.combined_javascript_path
      print = @javascript_fingerprint || ''
      File.join('javascripts', "site-#{print}.js")
    end

    def self.write_files(site, source, dest)
      site.static_files << StaticFileContent.new(source, dest)
    end

    def self.compile_sass_file(path, options)
      ::Sass.compile_file(path, options)
    end

    def self.compile_sass(contents, options)
      ::Sass.compile(contents, options)
    end

    def self.sass_config(site, item, default)
      if site.config['sass'] && site.config['sass'][item]
        site.config['sass'][item]
      else
        default
      end
    end
    
    def self.sass_options(site)
      options = {
        style:        sass_config(site, 'output_style', 'compressed').to_sym,
        trace:        sass_config(site, 'trace', false),
        line_numbers: sass_config(site, 'line_numbers', false)
      }
    end

    def self.write_combined_stylesheet(site)
      css = combine_stylesheets(site)
      css.keys.each do |media|
        options = sass_options(site)
        options[:line_numbers] = false
        contents = compile_sass(css[media][:contents], options)
        write_files(site, contents, combined_stylesheet_path(media)) 
      end
    end

    def self.write_combined_javascript(site)
      js = combine_javascripts(site)
      write_files(site, js, combined_javascript_path) unless js == ''
    end

    def self.combine_stylesheets(site)
      unless @combined_stylesheets
        css = {}
        paths = {}
        plugins.each do |plugin|
          plugin_header = "/* #{name} #{plugin.type} */\n"
          stylesheets = plugin.stylesheets.clone.concat plugin.sass
          stylesheets.each do |file|
            css[file.media] ||= {}
            css[file.media][:contents] ||= ''
            css[file.media][:contents] << plugin_header
            css[file.media][:paths] ||= []
            
            # Add Sass files
            if file.respond_to? :compile
              css[file.media][:contents].concat file.compile(site)
            else
              css[file.media][:contents].concat file.path(site).read.strip
            end
            css[file.media][:paths] << file.path(site)
            plugin_header = ''
          end
        end

        css.keys.each do |media|
          css[media][:fingerprint] = fingerprint(css[media][:paths])
        end
        @combined_stylesheets = css
      end
      @combined_stylesheets
    end

    def self.combine_javascripts(site)
      unless @combined_javascripts
        js = ''
        plugins.each do |plugin| 
          paths = plugin.javascript_paths(site)
          @javascript_fingerprint = fingerprint(paths)
          paths.each do |file|
            js.concat Pathname.new(file).read
          end
        end
        @combined_javascripts = js
      end
      @combined_javascripts
    end

    def self.combined_stylesheet_tag(site)
      tags = ''
      combine_stylesheets(site).keys.each do |media|
        tags.concat "<link href='/#{combined_stylesheet_path(media)}' media='#{media}' rel='stylesheet' type='text/css'>"
      end
      tags
    end

    def self.combined_javascript_tag(site)
      unless combine_javascripts(site) == ''
        "<script src='/#{combined_javascript_path}'></script>"
      end
    end

    def self.stylesheet_tags
      css = []
      plugins.each do |plugin| 
        css.concat plugin.stylesheet_tags
        css.concat plugin.sass_tags
      end
      css
    end

    def self.javascript_tags
      js = []
      plugins.each do |plugin| 
        js.concat plugin.javascript_tags
      end
      js
    end

    def self.copy_javascripts(site)
      plugins.each do |plugin| 
        copy(plugin.javascripts, site)
      end
    end

    def self.copy_stylesheets(site)
      plugins.each do |plugin| 
        stylesheets = plugin.stylesheets.clone.concat plugin.sass
        copy(stylesheets, site)
      end
    end

    def self.add_static_files(site)
     
      if site.config['sass'] and site.config['sass']['files']
        plugin('sass').add_files site.config['sass']['files']
      end
 
      # Copy/Generate Stylesheets
      #
      if site.config['octopress'] && site.config['octopress']['combine_stylesheets'] != false
        copy_stylesheets(site)
      else
        write_combined_stylesheet(site)
      end

      # Copy/Generate Javascripts
      #
      if site.config['octopress'] && site.config['octopress']['combine_javascripts'] != false
        copy_javascripts(site)
      else
        write_combined_javascript(site)
      end

      # Copy other assets
      #
      copy_static_files(site)
    end

    def self.copy_static_files(site)
      plugins.each do |plugin| 
        copy(plugin.files, site)
        copy(plugin.images, site)
        copy(plugin.fonts, site)
      end
    end

    def self.copy(files, site)
      files.each { |f| f.copy(site) }
    end
  end
end

