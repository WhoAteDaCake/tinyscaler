require "yaml"
require "path"
require "pg"

require "./spec"
require "./instances"

# https://github.com/will/crystal-pg/issues/125

spec = File.open(ARGV[0]) do |file|
  Config.from_yaml(file)
end

instance = Instances.new((Path[spec.paths.directory].join spec.paths.compose_file), spec)

DB.connect(spec.connection.url) do | conn |
  while true
    puts "[Scaler] Syncing"
    instance.read_current spec.stack

    puts "[Scaler] Looking for updates:"
    updates = instance.find_updates(conn, spec.stack)
    if updates.size != 0
      puts "[Scaler] Scaling #{updates.size} services:"
      Process.run(
        "docker",
        ["service", "scale"] + updates,
        error: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit
      )
    else
      puts "[Scaler] No updates found"
    end

    sleep spec.polling.timeout.seconds
  end
end