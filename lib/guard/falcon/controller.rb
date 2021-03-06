# Copyright, 2017, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'guard/compat/plugin'

require 'rack/builder'
require 'rack/server'

require 'async/logger'
require 'async/container'

require 'async/io/host_endpoint'
require 'async/io/shared_endpoint'

require 'falcon/server'
require 'falcon/endpoint'

module Guard
	module Falcon
		class Controller < Plugin
			DEFAULT_OPTIONS = {
				config: 'config.ru',
				count: 1,
				verbose: false,
			}

			def initialize(**options)
				super
				
				@options = DEFAULT_OPTIONS.merge(options)
				@endpoint = nil
				@container = nil
			end

			# As discussed in https://github.com/guard/guard/issues/713
			def logger
				Async.logger
			end
			
			private def build_endpoint
				# Support existing use cases where only port: is specified.
				if @options[:endpoint]
					return @options[:endpoint]
				else
					url = @options.fetch(:url, "https://localhost")
					port = @options.fetch(:port, 9292)
					
					return ::Falcon::Endpoint.parse(url, port: port)
				end
			end
			
			def endpoint
				@endpoint ||= build_endpoint
			end
			
			def run_server(container = Async::Container::Threaded.new)
				@bound_endpoint ||= Async::Reactor.run do
					Async::IO::SharedEndpoint.bound(endpoint)
				end.wait
				
				logger.info("Starting Falcon HTTP server on #{endpoint}.")
				
				container.run(count: @options[:count], restart: true, name: "Guard::Falcon: #{endpoint}") do
					begin
						rack_app, options = Rack::Builder.parse_file(@options[:config])
					rescue => error
						logger.error(error) {"Failed to load #{@options[:config]}"}
					end
					
					app = ::Falcon::Server.middleware(rack_app, verbose: @options[:verbose])
					server = ::Falcon::Server.new(app, @bound_endpoint, endpoint.protocol, endpoint.scheme)
					
					server.run
				end
				
				return container
			end

			def start
				@container = run_server
			end

			def running?
				!@container.nil?
			end

			def reload
				stop
				start
			end

			def stop
				if @container
					@container.stop(false)
					@container = nil
				end
			end

			def run_on_change(paths)
				reload
			end
		end
	end
end
