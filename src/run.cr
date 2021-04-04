require "yaml"
require "path"

# https://github.com/will/crystal-pg/issues/125

alias ProcessCounts = Hash(String, Int8)

root_dir = "/home/ubuntu/projects/pipeline-monorepo/system"
docker_file = "docker-compose.yaml"
SIZE_RE = /_(\d)+$/

def read_services(compose_path)
  yaml = File.open(compose_path) do |file|
    YAML.parse(file)
  end

  services = yaml["services"].as_h
  services.reduce(ProcessCounts.new) do |acc, (key, value)|
    acc[key.as_s] = 0
    acc
  end
end

def read_status(path)
  base_l = (Path[path].basename).size + 1
  io = IO::Memory.new
  Process.run("docker-compose", ["ps"], output: io, chdir: path)
  io.close
  output = io.to_s.split "\n"
  output[2, output.size - 2]
    .select do | row | row.size != 0 end
    .reduce(ProcessCounts.new) do | acc, row |
      name = (row.split)[0]
      count = (SIZE_RE.match(name).try &.[1])
      if !count.nil?
        name = name[base_l, name.size + 1]
        name = name[0, name.size - count.size - 1]
        acc[name] = count.to_i8
      end
      acc
    end
end

def update_status(status, dir)
  n_status = read_status dir
  status.merge! n_status
end

service_status = read_services(Path[root_dir].join docker_file)
service_status = update_status(service_status, root_dir)
puts service_status