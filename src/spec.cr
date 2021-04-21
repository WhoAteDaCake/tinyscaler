require "yaml"
require "json"

class Config
  include YAML::Serializable
  
  class Connection
    include YAML::Serializable

    property url : String
  end

  class Polling
    include YAML::Serializable
    property timeout : Int8
  end

  class Paths
    include YAML::Serializable
    property directory : String
    property compose_file : String
  end

  property query : Hash(String, String)
  property connection : Connection
  property polling : Polling
  property paths : Paths
  property stack : String
end

class ComposeFile
  include YAML::Serializable

  class Services
    include YAML::Serializable

    @[YAML::Field(emit_null: true)]
    property labels : Array(String) ?
  end
  
  property services : Hash(String, Services)
end

class ServicesOutput
  include JSON::Serializable

  property name : String
  property replicas : String
end