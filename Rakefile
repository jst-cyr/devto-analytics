require 'rake'
require_relative 'lib/devto_analytics'

namespace :devto do
  desc 'Collect analytics for an organization'
  task :collect, [:org, :since] do |t, args|
    args.with_defaults(org: ENV['DEVTO_ORG_SLUG'], since: ENV['DEVTO_SINCE'] || '2025-06-01')
    raise "No organization provided. Set DEVTO_ORG_SLUG or pass org argument." unless args[:org]
    collector = DevtoAnalytics::Collector.new(org: args[:org], since: args[:since])
    collector.run(write: true)
  end

  desc 'Dry run: log what would be collected'
  task :dry_run, [:org, :since] do |t, args|
    args.with_defaults(org: ENV['DEVTO_ORG_SLUG'], since: ENV['DEVTO_SINCE'] || '2025-06-01')
    raise "No organization provided. Set DEVTO_ORG_SLUG or pass org argument." unless args[:org]
    collector = DevtoAnalytics::Collector.new(org: args[:org], since: args[:since])
    collector.run(write: false)
  end
end

desc 'Run specs'
task :test do
  sh 'bundle exec rspec'
end
