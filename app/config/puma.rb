# Puma config

workers_count = Integer(ENV['WEB_WORKERS'] || 4)
threads_count = Integer(ENV['MAX_THREADS'] || 5)

workers(workers_count)
threads(threads_count, threads_count)

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'
