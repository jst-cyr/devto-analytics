require 'sinatra/base'
require 'json'

module DevtoAnalytics
  class Server < Sinatra::Base
    set :root, File.dirname(__FILE__)
    set :public_folder, Proc.new { File.join(root, 'public') }
    set :views, Proc.new { File.join(root, 'views') }

    get '/' do
      # Find the latest data directory
      data_root = File.join(Dir.pwd, 'data')
      latest_dir = Dir.glob(File.join(data_root, '*')).select { |f| File.directory?(f) }.sort.last

      @data = []
      @org = 'Unknown'
      @date = 'Unknown'

      if latest_dir
        json_file = Dir.glob(File.join(latest_dir, '*.json')).first
        if json_file
          @data = JSON.parse(File.read(json_file))
          filename = File.basename(json_file)
          if filename =~ /(.+)-analytics-(.+)\.json/
            @org = $1
            @date = $2
          end
        end
      end

      erb :index
    end

    run! if app_file == $0
  end
end
