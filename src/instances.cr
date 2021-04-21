ID_LABEL = "autoscaler.id"
DEPENDENCIES_LABEL = "autoscaler.dependencies"
QUERY_LABEL = "autoscaler.query"
# Addition of + 1 is for the dot removal
QUERY_LABEL_OFFSET = QUERY_LABEL.size + 1
ID_LABEL_OFFSET = ID_LABEL.size + 1
DEPENDENCIES_LABEL_OFFSET = DEPENDENCIES_LABEL.size + 1

alias ProcessCounts = Hash(String, Int32)

class Deployment
  property count : Int32
  property dependencies : Array(String)
  property query : String

  def initialize(@count : Int32, @dependencies : Array(String), @query : String)
  end
end

class Instances
  property processes : Hash(String, Deployment)

  def initialize(file : Path, config : Config)
    @processes = Hash(String, Deployment).new

    yaml = File.open(file) do |file|
      ComposeFile.from_yaml(file)
    end

    yaml.services.each do | k, v |
      v.labels.try do | labels |
        name = labels.find { |key| key.includes?(ID_LABEL) }
        name.try do | name |
          name = name[ID_LABEL_OFFSET, name.size]
          # DEPENDENCIES_LABEL
          dependencies = labels.reduce(Array(String).new) do | acc, label |
            if label.includes?(DEPENDENCIES_LABEL)
              acc << label[DEPENDENCIES_LABEL_OFFSET, label.size]
              acc
            else
              acc
            end
          end
          # QUERY_lABEL
          query = labels.find { |key| key.includes?(QUERY_LABEL) }
          query =
            if query.nil?
              config.query["default"]
            else
              config.query[query[QUERY_LABEL_OFFSET, query.size]]
            end
          @processes[name] = Deployment.new(0, dependencies, query)
        end
      end
    end
  end

  def read_current(stack : String)
    io = IO::Memory.new
    Process.run("docker",
      [
        "stack",
        "services",
        stack,
        "--format",
        "{ \"name\":{{json .Name }}, \"replicas\": {{json .Replicas }}}"
        ],
        output: io)
    io.close
    rows = io.to_s.split "\n"
    # Removes EOF
    rows = rows[0, rows.size - 1]

    base_l = stack.size + 1
    rows.each do | row |
      state = ServicesOutput.from_json(row)
      count = state.replicas.split("/")[1]
      # Removes the stack prefix
      name = state.name[base_l, state.name.size + 1]
      if @processes.has_key?(name)
        @processes[name].count = count.as(String).to_i
      end
    end
  end

  def find_updates(conn, stack)
    latest = @processes.reduce(ProcessCounts.new) do | acc, (k, p) |
      count = conn.scalar(p.query, k).as(Int32)
      acc[k] = count
      acc
    end

    latest.reduce(Array(String).new) do | acc, (k, v) |
      entry = @processes[k]
      if v != entry.count
        entry.count = v;
        acc + entry.dependencies.map { |d| "#{stack}_#{d}=#{v}" }
      else
        acc
      end
    end
  end
end