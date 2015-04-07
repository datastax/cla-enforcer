require 'rubygems'
require 'bundler/setup'

$: << File.expand_path('../lib', __FILE__)

namespace :db do
  desc "Prepare the database, this should be done automatically when using 'Deploy to Heroku' button"
  task :migrate do
    require 'cla'
    require 'sequel/extensions/migration'

    Sequel::Migrator.apply(Sequel.connect(ENV['DATABASE_URL']), 'schema')
  end
end

namespace :cla do
  desc "Set up pull request creation web hook to notify the CLA Enforcer"
  task :enforce, [:repository] do |t, args|
    require 'cla'
    p CLA.github.subscribe(args['repository'], '/github')
  end

  desc "Create a GitHub issue, mentioning all past contributors and asking them to sign the CLA"
  task :announce, [:repository] do |t, args|
    require 'cla'
    p CLA.github.announce(args['repository'], ENV['AGREEMENT_NAME'] || 'Contribution License Agreement')
  end

  desc "List logins of all contributors that haven't signed the CLA"
  task :missing, [:repository] do |t, args|
    require 'cla'
    puts CLA.github.missing(args['repository'])
  end
end
