# Copyright 2010-2011 Wincent Colaiuta. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'command-t/vim'
require 'command-t/scanner'
require 'digest/md5'

module CommandT
  # Reads the current directory recursively for the paths to all regular files.
  class FileScanner < Scanner
    class FileLimitExceeded < ::RuntimeError; end
    attr_accessor :path

    def initialize path = Dir.pwd, options = {}
      @paths                = {}
      @paths_keys           = []
      @path                 = path
      @max_depth            = options[:max_depth] || 15
      @max_files            = options[:max_files] || 10_000
      @max_caches           = options[:max_caches] || 1
      @scan_dot_directories = options[:scan_dot_directories] || false
      @cache_directory      = options[:cache_directory] || false
      @directories_to_save  = options[:directories_to_save] || false
      if @directories_to_save != false
        if !@directories_to_save.respond_to?('each')
          @directories_to_save = @directories_to_save.split
        end
      end
    end

    def paths
      return @paths[@path] if @paths.has_key?(@path)
      begin
        ensure_cache_under_limit
        @paths[@path] = []
        @depth        = 0
        @files        = 0
        @prefix_len   = @path.chomp('/').length

        if @cache_directory != false
          digest = Digest::MD5.hexdigest(@path)
          filepath = File.expand_path(@cache_directory + "/" + digest)

          # Check to see if there is a saved cache, if there is then load it.
          begin
            File.open(filepath, 'r') do |f|
              @paths[@path] = Marshal.load f.read
              return @paths[@path]
            end
          rescue
          end
        end

        add_paths_for_directory @path, @paths[@path]
      rescue FileLimitExceeded
      end

      begin
        # Save directories cache to file
        if @directories_to_save != false
          @directories_to_save.each do |directory|
            directory = File.expand_path(directory)
            current_path = File.expand_path(@path)
            if current_path.start_with?(directory)
              begin
                data = Marshal.dump(@paths[@path])
                f = File.new(filepath, 'w')
                f.write(data)
                f.close()
              rescue
              end
            end
          end
        end
      rescue
      end
      @paths[@path]
    end

    def flush
      @paths = {}

      if @cache_directory != false
        digest = Digest::MD5.hexdigest(@path)
        filepath = File.expand_path(@cache_directory + "/" + digest)
        begin
          # Flush will also delete the saved file
          File.delete(filepath)
        rescue
        end
      end
    end

  private

    def ensure_cache_under_limit
      # Ruby 1.8 doesn't have an ordered hash, so use a separate stack to
      # track and expire the oldest entry in the cache
      if @max_caches > 0 && @paths_keys.length >= @max_caches
        @paths.delete @paths_keys.shift
      end
      @paths_keys << @path
    end

    def path_excluded? path
      # first strip common prefix (@path) from path to match VIM's behavior
      path = path[(@prefix_len + 1)..-1]
      path = VIM::escape_for_single_quotes path
      ::VIM::evaluate("empty(expand(fnameescape('#{path}')))").to_i == 1
    end

    def add_paths_for_directory dir, accumulator
      Dir.foreach(dir) do |entry|
        next if ['.', '..'].include?(entry)
        path = File.join(dir, entry)
        unless path_excluded?(path)
          if File.file?(path)
            @files += 1
            raise FileLimitExceeded if @files > @max_files
            accumulator << path[@prefix_len + 1..-1]
          elsif File.directory?(path)
            next if @depth >= @max_depth
            next if (entry.match(/\A\./) && !@scan_dot_directories)
            @depth += 1
            add_paths_for_directory path, accumulator
            @depth -= 1
          end
        end
      end
    rescue Errno::EACCES
      # skip over directories for which we don't have access
    end
  end # class FileScanner
end # module CommandT
