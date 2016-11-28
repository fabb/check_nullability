#!/usr/bin/env ruby


# The MIT License (MIT)
# Copyright (c) 2016 Fabian Ehrentraud
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# This script checks headers for nullability annotations
# Note that each header is actually checked to contain at least ONE nullability annotation, as clang will warn about all missing nullability annotations in a header if at least one annotation in contained
# Main use is for checking the bridging header of a mixed Objective-C/Swift project in order to make using Objective-C code from Swift more safe
# It runs so fast that it can be run with every build in an own build phase


require 'set'
require 'optparse'
require 'ostruct'
require 'pathname'


options = parse(ARGV)

# calculating realpaths for the directories instead of all the headers contained saves a lot of time
options.include_paths = options.include_paths.map{|p| p.realpath}
options.exclude_paths = options.exclude_paths.map{|p| p.realpath}

all_headers = find_all_headers(options.include_paths, options.exclude_paths)

if all_headers.count == 0 then bail_out('no headers found in search folders', options.warn_only) end

recursive_imports = recursive_imports_in_file(options.header_file, all_headers)

if options.verbose
	not_found_imports = recursive_imports.select {|f| make_header_absolute_filename(f, all_headers) == nil}
	not_found_imports.each {|i|
		puts "import not found/excluded: " + i
	}
end

found_imports_absolute = recursive_imports.map {|f| make_header_absolute_filename(f, all_headers)}.compact
not_containing_nullability = found_imports_absolute.select {|f| not contains_any_nullability?(f)}

if not_containing_nullability.empty?
	exit 0
else
	# format in a way it will show up in xcode issue navigator
	warnings = not_containing_nullability.map {|pathname| pathname.to_s + ':0: ' + (options.warn_only ? 'warning' : 'error') + ': missing nullability in file ' + pathname.to_s}
	warnings_concatenated = warnings.join("\n")
	bail_out(warnings_concatenated, options.warn_only)
end


BEGIN {
	def parse(args)
		options = OpenStruct.new
		options.header_file = nil
		options.include_paths = [Pathname(".")]
		options.exclude_paths = []
		options.warn_only = false
		options.verbose = false

		opt_parser = OptionParser.new do |opts|
			opts.banner = "Usage: " + File.basename(__FILE__) + " [options] header_file.h"

			opts.separator ""
			opts.separator "header_file.h is the starting point for the search of nullability annotations, from there all #import statements will be followed recursively"

			opts.separator ""
			opts.separator "Specific options:"

			opts.on("-i x,y,z", "--include-paths PATH1,PATH2,PATH3", Array,
							"Comma-separated list of paths to search for headers found in include statements", "If not given, uses the current working directory as include path") do |include_paths|
				options.include_paths = include_paths
			end

			opts.on("-e x,y,z", "--exclude-paths PATH1,PATH2,PATH3", Array,
							"Comma-separated list of paths to exclude from the search for headers") do |exclude_paths|
				options.exclude_paths = exclude_paths
			end

			opts.on("-w", "--warn-only", "On missing nullability, exit with 0 nonetheless") do |w|
				options.warn_only = w
			end

			opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
				options.verbose = v
			end

			opts.separator ""
			opts.separator "Common options:"

			opts.on_tail("-h", "--help", "Show this message") do
				puts opts
				exit
			end
		end

		begin
			opt_parser.parse!
			unless ARGV.length == 1
				raise OptionParser::MissingArgument.new("missing header_file.h")
			end

			options.header_file = ARGV.pop

			options.header_file = Pathname(options.header_file)
			unless options.header_file.file?
				raise OptionParser::InvalidArgument.new("header_file.h not found at given location")
			end
			unless options.header_file.extname == ".h"
				raise OptionParser::InvalidArgument.new("header_file.h needs to have extension .h, given: " + options.header_file.extname)
			end

			options.include_paths.each {|p| 
				unless Pathname(p).directory?
					raise OptionParser::InvalidArgument.new("include_path not found at given location: " + p)
				end
			}
			options.include_paths = options.include_paths.map {|p| Pathname(p)}

			options.exclude_paths.each {|p| 
				unless Pathname(p).directory?
					raise OptionParser::InvalidArgument.new("exclude_path not found at given location: " + p)
				end
			}
			options.exclude_paths = options.exclude_paths.map {|p| Pathname(p)}

		rescue OptionParser::InvalidOption, OptionParser::InvalidArgument, OptionParser::MissingArgument
			puts $!.to_s
			puts options
			exit 1
		end

		options
	end

	# include_pathnames and exclude_pathnames expected to only contain realpaths
	def find_all_headers(include_pathnames, exclude_pathnames)
		include_pathnames
			.flat_map {|p| Pathname.glob(p+"**"+"*.h")}
			.uniq
			.select {|header_pathname|
				header_pathname.file? && exclude_pathnames.none? {|exclude_pathname|
					header_pathname.to_path.start_with?(exclude_pathname.to_path)
				}
			}
	end

	# extracts all header filenames that are imported in the given file
	def imports_in_file(file_pathname)
		file_pathname.readlines.map {|line| line[/.*#import[\s]*("|<)([^">]*)/, 2]}.compact
	end

	# returns the filenames as written in the imports
	def recursive_imports_in_file(file_pathname, all_header_pathnames, processed_imports_relative = Set.new)
		imports_relative = imports_in_file(file_pathname)
		unprocessed_imports_relative = imports_relative.select {|f| !processed_imports_relative.include?(f)}
		processed_imports_relative += unprocessed_imports_relative
		# implicitly removes imports that are not contained in all_header_pathnames
		import_pathnames = unprocessed_imports_relative.map {|f| make_header_absolute_filename(f, all_header_pathnames)}.compact

		import_pathnames.each {|p|
			processed_imports_relative += recursive_imports_in_file(p, all_header_pathnames, processed_imports_relative)
		}
		return processed_imports_relative
	end

	# all_header_pathnames expected to only contain realpaths
	def make_header_absolute_filename(filename, all_header_pathnames)
		all_header_pathnames.find {|p| p.to_path.end_with?(filename)}
	end

	def contains_any_nullability?(file_pathname)
		nullability_cues = ['NS_ASSUME_NONNULL_BEGIN', 'nullable', 'nonnull', '_Nullable', '_Nonnull']
		file_pathname.readlines.any? {|line| nullability_cues.any? {|nullability_cue| line.include?(nullability_cue)} }
	end

	def bail_out(message, warn_only)
		$stderr.puts message
		if warn_only
			exit 0
		else
			exit 1
		end
	end
}
