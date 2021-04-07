ID_LABEL = "autoscaler.id"
DEPENDENCIES_LABEL = "autoscaler.dependencies"
ID_LABEL_OFFSET = ID_LABEL.size + 1
DEPENDENCIES_LABEL_OFFSET = DEPENDENCIES_LABEL.size + 1

alias ProcessCounts = Hash(String, Int32)

class Instances
  property labels : ProcessCounts
  property dependencies : Hash(String, Array(String))

  def initialize(file : Path)
    @labels = ProcessCounts.new
    @dependencies = Hash(String, Array(String)).new

    yaml = File.open(file) do |file|
      ComposeFile.from_yaml(file)
    end

    yaml.services.each do | k, v |
      v.labels.try do | labels |
        name = labels.find { |key| key.includes?(ID_LABEL) }
        name.try do | name |
          name = name[ID_LABEL_OFFSET, name.size]
          @labels[name] = 0
          @dependencies[name] = labels.reduce(Array(String).new) do | acc, label |
            if label.includes?(DEPENDENCIES_LABEL)
              acc << label[DEPENDENCIES_LABEL_OFFSET, label.size]
              acc
            else
              acc
            end
          end
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
      if @labels.has_key?(name)
        @labels[name] = count.as(String).to_i
      end
    end
  end

  def find_updates(conn, query, stack)
    latest = @labels.reduce(ProcessCounts.new) do | acc, (k, v) |
      count = conn.scalar(query, k).as(Int32)
      acc[k] = count
      acc
    end

    latest.reduce(Array(String).new) do | acc, (k, v) |
      if v != @labels[k]
        @labels[k] = v;
        acc + @dependencies[k].map! { |d| "#{stack}_#{d}=#{v}" }
      else
        acc
      end
    end
  end
end